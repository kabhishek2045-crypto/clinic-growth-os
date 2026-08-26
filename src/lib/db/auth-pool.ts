import { Pool } from 'pg';
import { getEnv } from '@/config/env';

/**
 * The connection Better Auth uses, deliberately separate from the tenant pool.
 *
 * It lives here rather than in src/lib/auth because every `pg` import belongs in
 * the data layer — the no-restricted-imports rule in eslint.config.mjs enforces
 * that, and it caught this file's first draft sitting in the wrong directory.
 *
 * Two settings are load-bearing:
 *
 *   role         clinic_os_auth reaches app."user", app."session", app."account"
 *                and app."verification" and nothing else. clinic_os_app has no
 *                grant on them, so injection in the tenant path cannot lift a
 *                session token or a password hash.
 *   search_path  Better Auth's model names are unqualified and would otherwise
 *                resolve to `public`. This puts them in schema app.
 */
declare global {
  var __clinicOsAuthPool: Pool | undefined;
}

export function getAuthPool(): Pool {
  if (!globalThis.__clinicOsAuthPool) {
    const env = getEnv();
    if (!env.DATABASE_URL_AUTH) {
      throw new Error(
        'DATABASE_URL_AUTH is required: the auth tables are reachable only by clinic_os_auth. ' +
          'See migrations/0006_better_auth.sql.',
      );
    }
    globalThis.__clinicOsAuthPool = new Pool({
      connectionString: env.DATABASE_URL_AUTH,
      options: '-c search_path=app',
      max: 5,
    });
  }
  return globalThis.__clinicOsAuthPool;
}

export async function closeAuthPool(): Promise<void> {
  if (globalThis.__clinicOsAuthPool) {
    await globalThis.__clinicOsAuthPool.end();
    globalThis.__clinicOsAuthPool = undefined;
  }
}
