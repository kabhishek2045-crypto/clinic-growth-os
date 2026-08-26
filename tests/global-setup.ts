import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readFile } from 'node:fs/promises';
import EmbeddedPostgres from 'embedded-postgres';
import { Client } from 'pg';

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
    console.log('[rls] using the configured DATABASE_URL');
    return;
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

  // Migrations run as the owner.
  const owner = new Client({ connectionString: ownerUrl });
  await owner.connect();
  const sql = await readFile(join(process.cwd(), 'migrations', '0001_tenancy_spike.sql'), 'utf8');
  await owner.query(sql);
  // The migration creates clinic_os_app NOLOGIN. Tests must actually connect as
  // it, so grant it a login here — local and ephemeral, never in production.
  await owner.query(`ALTER ROLE clinic_os_app LOGIN PASSWORD '${APP_PASSWORD}'`);
  await owner.end();

  process.env.DATABASE_URL_UNPOOLED = ownerUrl;
  process.env.DATABASE_URL = appUrl;
  console.log(`[rls] postgres ready on :${port}`);
}

export async function teardown(): Promise<void> {
  if (pg) await pg.stop();
  if (dataDir) await rm(dataDir, { recursive: true, force: true });
}
