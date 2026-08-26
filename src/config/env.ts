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
  VERCEL_API_TOKEN: z.string().optional(), // M3
  VERCEL_PROJECT_ID: z.string().optional(), // M3
  VERCEL_TEAM_ID: z.string().optional(), // M3
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
