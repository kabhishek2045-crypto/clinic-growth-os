import { Pool, type PoolClient } from 'pg';
import { getEnv } from '@/config/env';

/**
 * MASTER_PROMPT §9.1.
 *
 * Driver note: node-postgres over TCP, not the @neondatabase/serverless HTTP
 * driver. The HTTP driver issues each statement as an independent request and
 * holds no session state, so `SET LOCAL` cannot survive to the next query — which
 * makes the §9.1 bridge impossible on it. node-postgres talks the standard
 * Postgres wire protocol and works unchanged against local Postgres in tests and
 * against Neon from Vercel's Node runtime.
 *
 * If a future feature genuinely needs Edge runtime, that path gets the HTTP
 * driver for non-tenant-scoped reads only (e.g. domain resolution), never for
 * tenant data.
 */

const EXPECTED_ROLE = 'clinic_os_app';

declare global {
  var __clinicOsPool: Pool | undefined;
  var __clinicOsIdentityCheck: Promise<void> | undefined;
}

/**
 * The entire isolation model rests on connecting as clinic_os_app, and that rests
 * on one environment variable. Vercel's Neon integration injects a neondb_owner
 * connection string by DEFAULT, and neondb_owner is a member of neon_superuser —
 * which can reach BYPASSRLS. Point DATABASE_URL at it and every policy in the
 * repo silently stops applying while the application keeps working perfectly.
 *
 * The isolation suite has a test for reachable-BYPASSRLS roles, but CI runs it
 * against a local postgres service, so it proves nothing about production's role
 * graph. This assertion runs against whatever the process actually connected to,
 * once, on the first connection.
 */
export async function assertConnectionIdentity(pool: Pool): Promise<void> {
  const res = await pool.query<{ current_user: string; privileged: boolean }>(
    `SELECT current_user,
            COALESCE((SELECT bool_or(r.rolbypassrls OR r.rolsuper)
                        FROM pg_roles r
                       WHERE pg_has_role(current_user, r.oid, 'USAGE')), false) AS privileged`,
  );
  const row = res.rows[0];
  if (!row) throw new Error('connection identity check returned no row');

  if (row.current_user !== EXPECTED_ROLE) {
    throw new Error(
      `Refusing to serve: connected as "${row.current_user}", expected "${EXPECTED_ROLE}". ` +
        'A table owner bypasses its own RLS policies, so this would silently disable ' +
        "every tenant boundary. Check DATABASE_URL — Vercel's Neon integration injects " +
        'the owner connection string by default.',
    );
  }
  if (row.privileged) {
    throw new Error(
      `Refusing to serve: role "${row.current_user}" can reach a role with BYPASSRLS or ` +
        "SUPERUSER, which disables every tenant policy. Roles created through Neon's API " +
        'or console are granted neon_superuser; create the app role in SQL instead.',
    );
  }
}

export function getPool(): Pool {
  if (!globalThis.__clinicOsPool) {
    const env = getEnv();
    const pool = new Pool({
      connectionString: env.DATABASE_URL,
      max: 10,
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 10_000,
      // A hung provider call inside withTenant() would otherwise pin a connection
      // indefinitely; a runaway query would hold one just as long.
      statement_timeout: 10_000,
      idle_in_transaction_session_timeout: 15_000,
    });
    globalThis.__clinicOsPool = pool;
    // Fire once, and make every later caller await the same verdict rather than
    // racing it. A failure here must reject queries, not be swallowed.
    globalThis.__clinicOsIdentityCheck = assertConnectionIdentity(pool);
  }
  return globalThis.__clinicOsPool;
}

/** Awaited by withTenant() before the first statement of every transaction. */
export async function ensureConnectionIdentity(): Promise<void> {
  getPool();
  await globalThis.__clinicOsIdentityCheck;
}

export type { PoolClient };

export async function closePool(): Promise<void> {
  if (globalThis.__clinicOsPool) {
    await globalThis.__clinicOsPool.end();
    globalThis.__clinicOsPool = undefined;
    globalThis.__clinicOsIdentityCheck = undefined;
  }
}
