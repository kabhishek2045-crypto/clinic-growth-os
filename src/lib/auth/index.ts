import { betterAuth } from 'better-auth';
import { randomUUID } from 'node:crypto';
import { getEnv } from '@/config/env';
import { getAuthPool } from '@/lib/db/auth-pool';

/**
 * Better Auth, configured against the three collisions a spike verified against
 * version 1.7.1 (see migrations/0006_better_auth.sql for the evidence).
 *
 * Every setting below is load-bearing. Removing one does not degrade gracefully:
 *
 *  generateId   Better Auth emits `"id" text primary key` by default. Our
 *               clinic_users.user_id is uuid and now carries a foreign key to
 *               app."user"."id", so the ids must be uuids or the FK is not
 *               constructible. Verified end to end: signUpEmail produced a valid
 *               uuid and a uuid FK accepted it.
 *
 *  search_path  Its model names are unqualified, so they resolve to `public`.
 *               Connecting with `-c search_path=app` puts them in our schema
 *               instead; the spike confirmed zero tables leak into public.
 *
 *  auth role    getAuthPool() connects as clinic_os_auth, which reaches the
 *               four auth tables and nothing else. clinic_os_app has no grant on
 *               them at all, so injection in the tenant path cannot lift a
 *               session token or a password hash. This is a grant boundary, not
 *               a policy one, because Better Auth reads `user` by email and
 *               `session` by token BEFORE any principal exists — a policy keyed
 *               on a principal would deadlock sign-in.
 *
 * Better Auth does NOT run migrations here. Its DDL lives in migration 0006,
 * applied by the owner role; clinic_os_auth has no DDL privilege.
 */

export function createAuth() {
  const env = getEnv();
  if (!env.BETTER_AUTH_SECRET) {
    throw new Error('BETTER_AUTH_SECRET is required to create the auth instance.');
  }
  return betterAuth({
    database: getAuthPool(),
    emailAndPassword: { enabled: true },
    secret: env.BETTER_AUTH_SECRET,
    baseURL: env.BETTER_AUTH_URL ?? `http://${env.PLATFORM_ROOT_DOMAIN}`,
    advanced: { database: { generateId: () => randomUUID() } },
  });
}
