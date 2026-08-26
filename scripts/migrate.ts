import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Client } from 'pg';
import { loadLocalEnv } from '../src/config/load-env';

loadLocalEnv();

/**
 * §38, §44 — migrations run as the OWNER role over the UNPOOLED connection.
 * The application's own DATABASE_URL points at clinic_os_app, which cannot run
 * DDL, so this script deliberately requires a different credential.
 */
const MIGRATIONS_DIR = join(process.cwd(), 'migrations');

async function main(): Promise<void> {
  const url = process.env.DATABASE_URL_UNPOOLED ?? process.env.MIGRATION_DATABASE_URL;
  if (!url) {
    throw new Error(
      'Set DATABASE_URL_UNPOOLED (owner role) to run migrations. ' +
        'The app role clinic_os_app cannot and must not run DDL.',
    );
  }

  const client = new Client({ connectionString: url });
  await client.connect();

  await client.query(`
    CREATE TABLE IF NOT EXISTS public.schema_migrations (
      filename    text PRIMARY KEY,
      applied_at  timestamptz NOT NULL DEFAULT now()
    )
  `);

  const applied = new Set(
    (
      await client.query<{ filename: string }>('SELECT filename FROM public.schema_migrations')
    ).rows.map((r) => r.filename),
  );

  const files = (await readdir(MIGRATIONS_DIR)).filter((f) => f.endsWith('.sql')).sort();

  let count = 0;
  for (const file of files) {
    if (applied.has(file)) continue;
    const sql = await readFile(join(MIGRATIONS_DIR, file), 'utf8');
    process.stdout.write(`applying ${file} ... `);
    try {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query('INSERT INTO public.schema_migrations (filename) VALUES ($1)', [file]);
      await client.query('COMMIT');
      process.stdout.write('ok\n');
      count += 1;
    } catch (error) {
      await client.query('ROLLBACK');
      process.stdout.write('FAILED\n');
      throw error;
    }
  }

  await client.end();
  console.log(count === 0 ? 'no pending migrations' : `${count} migration(s) applied`);
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
