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

declare global {
  var __clinicOsPool: Pool | undefined;
}

export function getPool(): Pool {
  if (!globalThis.__clinicOsPool) {
    const env = getEnv();
    globalThis.__clinicOsPool = new Pool({
      connectionString: env.DATABASE_URL,
      max: 10,
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 10_000,
    });
  }
  return globalThis.__clinicOsPool;
}

export type { PoolClient };

export async function closePool(): Promise<void> {
  if (globalThis.__clinicOsPool) {
    await globalThis.__clinicOsPool.end();
    globalThis.__clinicOsPool = undefined;
  }
}
