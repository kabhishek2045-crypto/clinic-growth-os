import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Client, Pool, PoolClient } from 'pg';
import { appPool, ownerClient, seed, truncateAll, type Fixture } from '../helpers/db';

/**
 * What an attacker gets from forging a session GUC.
 *
 * Postgres has no ACL on custom settings, so anything able to execute arbitrary
 * SQL as clinic_os_app can SET LOCAL whatever it likes. Before migration 0008
 * that was total compromise: policies trusted app.current_org_ids, so claiming
 * another organization's uuid handed over its whole record set, and claiming
 * app.is_platform_admin = 'true' handed over the platform.
 *
 * These tests forge each value deliberately and assert it buys nothing. They are
 * the justification for that migration — without them the change is unverified
 * architecture.
 */

let owner: Client;
let pool: Pool;
let fx: Fixture;

async function forging<T>(
  settings: [string, string][],
  fn: (c: PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const [k, v] of settings) {
      await client.query('SELECT set_config($1, $2, true)', [k, v]);
    }
    return await fn(client);
  } finally {
    await client.query('ROLLBACK').catch(() => undefined);
    client.release();
  }
}

beforeAll(async () => {
  owner = ownerClient();
  await owner.connect();
  await truncateAll(owner);
  fx = await seed(owner);
  pool = appPool();
});

afterAll(async () => {
  await pool?.end();
  await owner?.end();
});

describe('forging app.current_org_ids buys nothing', () => {
  it('claiming another tenant with no user id yields no rows', async () => {
    const n = await forging(
      [['app.current_org_ids', fx.orgB]],
      async (c) => (await c.query('SELECT id FROM app.patients')).rows.length,
    );
    expect(n).toBe(0);
  });

  it("claiming another tenant WHILE authenticated as A still yields only A's rows", async () => {
    const rows = await forging(
      [
        ['app.current_user_id', fx.userA],
        ['app.current_org_ids', `${fx.orgA},${fx.orgB}`],
      ],
      async (c) =>
        (await c.query<{ id: string }>('SELECT id FROM app.patients')).rows.map((r) => r.id),
    );
    expect([...rows].sort()).toEqual([fx.patientA, fx.patientA2].sort());
    expect(rows).not.toContain(fx.patientB);
  });

  it('no policy reads the setting at all — it is inert', async () => {
    const derived = await forging(
      [
        ['app.current_user_id', fx.userA],
        ['app.current_org_ids', fx.orgB],
      ],
      async (c) => (await c.query<{ o: string[] }>('SELECT app.current_org_ids() AS o')).rows[0]?.o,
    );
    expect(derived).toEqual([fx.orgA]);
  });
});

describe('forging platform administration buys nothing', () => {
  it('setting app.is_platform_admin directly is ignored', async () => {
    const n = await forging(
      [
        ['app.current_user_id', fx.userA],
        ['app.is_platform_admin', 'true'],
      ],
      async (c) => (await c.query('SELECT id FROM app.patients')).rows.length,
    );
    expect(n).toBe(2); // A's own two patients, not all three
  });

  it('requesting elevation as a non-admin is ignored', async () => {
    const admin = await forging(
      [
        ['app.current_user_id', fx.userA],
        ['app.request_elevation', 'true'],
      ],
      async (c) =>
        (await c.query<{ a: boolean }>('SELECT app.is_platform_admin() AS a')).rows[0]?.a,
    );
    expect(admin).toBe(false);
  });

  it('a real admin who did NOT request elevation is not elevated', async () => {
    const admin = await forging(
      [['app.current_user_id', fx.adminUser]],
      async (c) =>
        (await c.query<{ a: boolean }>('SELECT app.is_platform_admin() AS a')).rows[0]?.a,
    );
    expect(admin).toBe(false);
  });

  it('elevation needs BOTH the request and a live grant', async () => {
    const admin = await forging(
      [
        ['app.current_user_id', fx.adminUser],
        ['app.request_elevation', 'true'],
      ],
      async (c) =>
        (await c.query<{ a: boolean }>('SELECT app.is_platform_admin() AS a')).rows[0]?.a,
    );
    expect(admin).toBe(true);
  });
});

describe('derivation is live, not a snapshot', () => {
  it('revoking membership takes effect on the next statement', async () => {
    // A snapshot taken at set_tenant_context time would keep serving rows to a
    // user whose access was just revoked, for the life of the transaction.
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT app.set_tenant_context($1)', [fx.userA]);
      const before = await client.query('SELECT id FROM app.patients');
      expect(before.rows.length).toBe(2);

      await owner.query(`UPDATE app.clinic_users SET deleted_at = now() WHERE user_id = $1`, [
        fx.userA,
      ]);

      const after = await client.query('SELECT id FROM app.patients');
      expect(after.rows.length).toBe(0);
    } finally {
      await client.query('ROLLBACK').catch(() => undefined);
      client.release();
      await owner.query(`UPDATE app.clinic_users SET deleted_at = NULL WHERE user_id = $1`, [
        fx.userA,
      ]);
    }
  });
});
