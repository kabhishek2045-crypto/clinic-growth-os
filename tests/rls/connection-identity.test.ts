import { afterAll, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { assertConnectionIdentity } from '@/lib/db/client';
import { requireUrls } from '../helpers/db';

/**
 * The isolation model rests on connecting as clinic_os_app, and that rests on one
 * environment variable. Vercel's Neon integration injects a neondb_owner
 * connection string by default, and a table's owner bypasses its own RLS
 * policies — so a misconfigured DATABASE_URL disables every tenant boundary in
 * the repo while the application keeps working perfectly.
 *
 * The existing reachable-BYPASSRLS test runs against whatever CI provisions, so
 * it proves nothing about production's role graph. This checks the live
 * connection.
 */

const pools: Pool[] = [];
const pool = (connectionString: string) => {
  const p = new Pool({ connectionString, max: 1 });
  pools.push(p);
  return p;
};

afterAll(async () => {
  await Promise.all(pools.map((p) => p.end().catch(() => undefined)));
});

describe('the process refuses to serve on the wrong connection', () => {
  it('accepts the app role', async () => {
    await expect(assertConnectionIdentity(pool(requireUrls().appUrl))).resolves.toBeUndefined();
  });

  it('REFUSES the owner connection — the Vercel default', async () => {
    await expect(assertConnectionIdentity(pool(requireUrls().ownerUrl))).rejects.toThrow(
      /Refusing to serve/,
    );
  });

  it('names the actual role it found, so the fix is obvious', async () => {
    await expect(assertConnectionIdentity(pool(requireUrls().ownerUrl))).rejects.toThrow(
      /expected "clinic_os_app"/,
    );
  });

  it('refuses the auth role too — it is not the tenant role', async () => {
    const authUrl = process.env.DATABASE_URL_AUTH;
    expect(authUrl).toBeTruthy();
    await expect(assertConnectionIdentity(pool(authUrl as string))).rejects.toThrow(
      /Refusing to serve/,
    );
  });
});
