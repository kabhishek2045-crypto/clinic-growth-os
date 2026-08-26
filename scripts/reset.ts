import { Client } from 'pg';
import { loadLocalEnv } from '../src/config/load-env';

loadLocalEnv();

/**
 * Drops the app schema and the migration ledger so migrations can be re-applied
 * from scratch. Development only.
 *
 * It deliberately does NOT drop the clinic_os_app role.
 *
 * Dropping and recreating that role against a live Neon project wedges the
 * connection pooler: it caches the role's OID, and every pooled connection then
 * fails with "invalid role OID", followed by "permission denied for schema app"
 * even though the grants are correct. The direct endpoint keeps working, which
 * makes it look like an RLS problem rather than a pooler problem. Recovering
 * meant recreating the whole project.
 *
 * So: reset the schema, keep the role, set its password once at project setup.
 */
async function main(): Promise<void> {
  const url = process.env.DATABASE_URL_UNPOOLED ?? process.env.MIGRATION_DATABASE_URL;
  if (!url) throw new Error('Set DATABASE_URL_UNPOOLED (owner role) to reset the database.');

  if (process.env.NODE_ENV === 'production') {
    throw new Error('Refusing to reset the database with NODE_ENV=production.');
  }

  const client = new Client({ connectionString: url });
  await client.connect();
  await client.query('DROP SCHEMA IF EXISTS app CASCADE');
  await client.query('DROP TABLE IF EXISTS public.schema_migrations');
  await client.end();
  console.log('schema dropped. run `npm run db:migrate` to rebuild.');
  console.log('note: role clinic_os_app was left in place, on purpose (see this file).');
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
