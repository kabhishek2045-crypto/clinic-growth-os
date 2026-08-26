import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readFile } from 'node:fs/promises';
import EmbeddedPostgres from 'embedded-postgres';
import { Client } from 'pg';
import { loadLocalEnv } from '../src/config/load-env';

// globalSetup runs before setupFiles, and dotenv's default entrypoint reads only
// `.env`. Without this a configured Neon connection is silently ignored and the
// suite quietly falls back to the embedded server.
loadLocalEnv();

/**
 * §47, §62.3 — the acceptance gate is the test suite, and it must be runnable by
 * any collaborator on any machine without Docker, Homebrew, or admin rights.
 *
 * This boots a REAL Postgres from a binary vendored in node_modules, applies the
 * migrations as the owner, and gives clinic_os_app a password so the suite can
 * connect as the same unprivileged role the application uses. A mock would prove
 * nothing here.
 *
 * If DATABASE_URL is already set (CI's postgres service, or a Neon branch), that
 * is used instead and nothing is booted.
 */

let pg: EmbeddedPostgres | undefined;
let dataDir: string | undefined;

const APP_PASSWORD = 'app_password_local_only';

export async function setup(): Promise<void> {
  if (process.env.DATABASE_URL && process.env.DATABASE_URL_UNPOOLED) {
    if (!process.env.DATABASE_URL_AUTH) {
      throw new Error(
        'DATABASE_URL_AUTH is required alongside DATABASE_URL: since migration 0006 the ' +
          'auth tables are reachable only by clinic_os_auth, and fixtures need it.',
      );
    }
    const host = new URL(process.env.DATABASE_URL).host;
    console.log(`[rls] using the configured database at ${host}`);
    return;
  }

  // One of the two set is always a mistake -- almost certainly a half-configured
  // .env.local -- and falling back to the embedded server would hide it.
  if (process.env.DATABASE_URL || process.env.DATABASE_URL_UNPOOLED) {
    throw new Error(
      'Set BOTH DATABASE_URL and DATABASE_URL_UNPOOLED, or neither. ' +
        'Only one is set, which would silently run the isolation suite against ' +
        'the embedded server instead of the database you configured.',
    );
  }

  dataDir = await mkdtemp(join(tmpdir(), 'clinic-os-pg-'));
  const port = 54329;

  pg = new EmbeddedPostgres({
    databaseDir: dataDir,
    user: 'postgres',
    password: 'postgres',
    port,
    persistent: false,
  });

  console.log('[rls] initialising embedded postgres ...');
  await pg.initialise();
  await pg.start();
  await pg.createDatabase('clinic_os');

  const ownerUrl = `postgresql://postgres:postgres@localhost:${port}/clinic_os`;
  const appUrl = `postgresql://clinic_os_app:${APP_PASSWORD}@localhost:${port}/clinic_os`;

  // Migrations run as the owner. Discovered and applied in order rather than
  // named: a hardcoded filename silently stops covering migrations added later,
  // which is how the isolation suite ended up running against a schema that was
  // one migration behind.
  const owner = new Client({ connectionString: ownerUrl });
  await owner.connect();
  const migrationsDir = join(process.cwd(), 'migrations');
  const files = (await readdir(migrationsDir)).filter((f) => f.endsWith('.sql')).sort();
  if (files.length === 0) throw new Error('no migrations found in migrations/');
  for (const file of files) {
    await owner.query(await readFile(join(migrationsDir, file), 'utf8'));
  }
  console.log(`[rls] applied ${files.length} migration(s)`);
  // The migration creates clinic_os_app NOLOGIN. Tests must actually connect as
  // it, so grant it a login here — local and ephemeral, never in production.
  await owner.query(`ALTER ROLE clinic_os_app LOGIN PASSWORD '${APP_PASSWORD}'`);
  // Same for the auth role. Better Auth's tables are unreachable to every other
  // role by design (migration 0006), so fixtures need this connection.
  await owner.query(`ALTER ROLE clinic_os_auth LOGIN PASSWORD '${APP_PASSWORD}'`);
  await owner.end();

  process.env.DATABASE_URL_UNPOOLED = ownerUrl;
  process.env.DATABASE_URL = appUrl;
  process.env.DATABASE_URL_AUTH = `postgresql://clinic_os_auth:${APP_PASSWORD}@localhost:${port}/clinic_os`;
  console.log(`[rls] postgres ready on :${port}`);
}

export async function teardown(): Promise<void> {
  if (pg) await pg.stop();
  if (dataDir) await rm(dataDir, { recursive: true, force: true });
}
