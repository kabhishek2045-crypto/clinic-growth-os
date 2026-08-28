import { z } from 'zod';

/**
 * MASTER_PROMPT §36, §51, §58 — every environment variable is declared, validated
 * once at startup, and never read via bare process.env elsewhere.
 *
 * The split matters: `serverEnv` holds secrets that must never reach the browser
 * (§53). Nothing in this file is exported to a Client Component, and no variable
 * here is prefixed NEXT_PUBLIC_.
 */
const serverSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),

  // Neon — pooled for request work, unpooled for migrations (§36)
  DATABASE_URL: z.string().url(),
  DATABASE_URL_UNPOOLED: z.string().url().optional(),

  // Better Auth connects as clinic_os_auth, which reaches app."user",
  // app."session", app."account" and app."verification" and nothing else.
  // clinic_os_app has no grant on those tables at all, so injection in the
  // tenant path cannot reach a session token or a password hash.
  DATABASE_URL_AUTH: z.string().url().optional(),

  PLATFORM_ROOT_DOMAIN: z.string().min(1).default('localhost:3000'),
});

/**
 * Declared now, required later. Each becomes non-optional at the milestone that
 * implements its provider, so a missing credential fails at boot rather than at
 * the first patient-facing request.
 */
const deferredSchema = z.object({
  R2_ACCOUNT_ID: z.string().optional(), // M7
  R2_ACCESS_KEY_ID: z.string().optional(), // M7
  R2_SECRET_ACCESS_KEY: z.string().optional(), // M7
  R2_BUCKET_NAME: z.string().optional(), // M7
  BETTER_AUTH_SECRET: z.string().min(32).optional(), // M2
  BETTER_AUTH_URL: z.string().url().optional(), // M2
  // NOTE: MASTER_PROMPT §36 names these VERCEL_API_TOKEN / VERCEL_PROJECT_ID /
  // VERCEL_TEAM_ID. Those names cannot be used: Vercel reserves the VERCEL_
  // prefix for its own system variables and rejects any project variable that
  // starts with it. Renamed by role rather than by vendor, which also suits §46
  // better — a future DomainProvider that is not Vercel keeps the same names.
  DOMAIN_PROVIDER_TOKEN: z.string().optional(), // M3
  DOMAIN_PROVIDER_PROJECT_ID: z.string().optional(), // M3
  DOMAIN_PROVIDER_TEAM_ID: z.string().optional(), // M3
});

const schema = serverSchema.merge(deferredSchema);

export type Env = z.infer<typeof schema>;

let cached: Env | undefined;

export function getEnv(): Env {
  if (cached) return cached;
  const parsed = schema.safeParse(process.env);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `  ${i.path.join('.')}: ${i.message}`).join('\n');
    throw new Error(`Invalid environment configuration:\n${issues}`);
  }
  cached = parsed.data;
  return cached;
}
