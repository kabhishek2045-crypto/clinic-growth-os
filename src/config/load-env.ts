import { config } from 'dotenv';

/**
 * Loads .env.local then .env, in that order, for scripts and tests.
 *
 * dotenv's default entrypoint reads only `.env`, which silently ignored a
 * configured .env.local — the migration runner reported "no owner connection"
 * while the file sat right there, and the isolation suite quietly ran against
 * the embedded server instead of the database that was configured. Both are the
 * same bug, so it lives in one place now.
 *
 * Next.js loads .env.local itself; this is only for code run outside it.
 */
export function loadLocalEnv(): void {
  config({ path: '.env.local', quiet: true });
  config({ quiet: true });
}
