import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Client, Pool, PoolClient } from 'pg';
import { appPool, ownerClient, seed, truncateAll, type Fixture } from '../helpers/db';
import { withPlatformAdmin, withTenant } from '@/lib/db/tenant';
import { sql } from '@/lib/db/sql';
import { closePool } from '@/lib/db/client';

/**
 * MASTER_PROMPT §47 — "Automated tests MUST attempt cross-tenant access and prove
 * that it fails."
 *
 * These run as clinic_os_app, the same role the application uses. Every assertion
 * is about what the DATABASE refuses, not what application code declines to ask
 * for — application-layer filtering is explicitly not a control here (§53).
 */

let owner: Client;
let pool: Pool;
let fx: Fixture;

/** Mirrors withTenant() exactly: BEGIN, derive context from the user id, run, roll back. */
async function asUser<T>(userId: string, fn: (c: PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT app.set_tenant_context($1)', [userId]);
    return await fn(client);
  } finally {
    await client.query('ROLLBACK').catch(() => undefined);
    client.release();
  }
}

/** No context set at all — the unconfigured-request case. */
async function asNobody<T>(fn: (c: PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
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
  await closePool();
  await pool?.end();
  await owner?.end();
});

describe('the app role cannot escape RLS', () => {
  it('does not own the tables it queries', async () => {
    const res = await owner.query<{ tableowner: string }>(
      `SELECT tableowner FROM pg_tables WHERE schemaname = 'app' AND tablename = 'patients'`,
    );
    expect(res.rows[0]?.tableowner).not.toBe('clinic_os_app');
  });

  it('has neither BYPASSRLS nor SUPERUSER', async () => {
    const res = await owner.query<{ rolbypassrls: boolean; rolsuper: boolean }>(
      `SELECT rolbypassrls, rolsuper FROM pg_roles WHERE rolname = 'clinic_os_app'`,
    );
    expect(res.rows[0]?.rolbypassrls).toBe(false);
    expect(res.rows[0]?.rolsuper).toBe(false);
  });

  it('cannot REACH a role that has BYPASSRLS or SUPERUSER', async () => {
    // Specifically a Neon hazard. A role created through Neon's API or console is
    // granted neon_superuser; one created in SQL, as migration 0001 does, is not.
    // Checking the role's own attributes would not catch the difference, because
    // the escalation would come through membership rather than the attribute --
    // so check every role reachable via pg_has_role instead.
    const res = await owner.query<{ rolname: string }>(
      `SELECT r.rolname
         FROM pg_roles r
        WHERE pg_has_role('clinic_os_app', r.oid, 'USAGE')
          AND (r.rolbypassrls OR r.rolsuper)`,
    );
    expect(res.rows.map((r) => r.rolname)).toEqual([]);
  });

  it('has RLS both ENABLED and FORCED on every tenant table', async () => {
    const res = await owner.query<{
      relname: string;
      relrowsecurity: boolean;
      relforcerowsecurity: boolean;
    }>(
      `SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity
         FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'app' AND c.relkind = 'r'`,
    );
    expect(res.rows.length).toBeGreaterThan(0);
    for (const row of res.rows) {
      expect(row.relrowsecurity, `${row.relname} ENABLE`).toBe(true);
      expect(row.relforcerowsecurity, `${row.relname} FORCE`).toBe(true);
    }
  });

  it('cannot run DDL', async () => {
    await expect(
      asUser(fx.userA, (c) => c.query('CREATE TABLE app.should_not_exist (id int)')),
    ).rejects.toThrow();
  });
});

describe('Clinic A cannot reach Clinic B', () => {
  it('SELECT returns only its own patients', async () => {
    const rows = await asUser(fx.userA, async (c) => {
      const r = await c.query<{ id: string }>('SELECT id FROM app.patients');
      return r.rows.map((x) => x.id);
    });
    expect([...rows].sort()).toEqual([fx.patientA, fx.patientA2].sort());
    expect(rows).not.toContain(fx.patientB);
  });

  it("SELECT by B's primary key returns nothing — not an error, nothing", async () => {
    const rows = await asUser(fx.userA, async (c) => {
      const r = await c.query('SELECT id FROM app.patients WHERE id = $1', [fx.patientB]);
      return r.rows;
    });
    expect(rows).toHaveLength(0);
  });

  it("UPDATE targeting B's row affects zero rows", async () => {
    const count = await asUser(fx.userA, async (c) => {
      const r = await c.query('UPDATE app.patients SET full_name = $1 WHERE id = $2', [
        'hijacked',
        fx.patientB,
      ]);
      return r.rowCount;
    });
    expect(count).toBe(0);
  });

  it("DELETE targeting B's row affects zero rows", async () => {
    const count = await asUser(fx.userA, async (c) => {
      const r = await c.query('DELETE FROM app.patients WHERE id = $1', [fx.patientB]);
      return r.rowCount;
    });
    expect(count).toBe(0);
  });

  it("INSERT stamped with B's organization_id is REJECTED", async () => {
    // The write-side boundary. Note that dropping WITH CHECK from these FOR ALL
    // policies does NOT break this, because Postgres then reuses USING as the
    // check -- confirmed by mutation test. What this assertion actually guards is
    // the write rule itself, which is what breaks if a policy is ever split into
    // per-command policies and the INSERT case is missed.
    await expect(
      asUser(fx.userA, (c) =>
        c.query(
          `INSERT INTO app.patients (organization_id, clinic_id, full_name, phone)
           VALUES ($1, $2, 'planted', '+919999999999')`,
          [fx.orgB, fx.clinicB],
        ),
      ),
    ).rejects.toThrow(/row-level security/i);
  });

  it("cannot re-stamp its own row into B's tenant", async () => {
    await expect(
      asUser(fx.userA, (c) =>
        c.query('UPDATE app.patients SET organization_id = $1 WHERE id = $2', [
          fx.orgB,
          fx.patientA,
        ]),
      ),
    ).rejects.toThrow(/row-level security/i);
  });

  it('cannot enumerate B through a join, an aggregate, or a subquery', async () => {
    const out = await asUser(fx.userA, async (c) => {
      const joined = await c.query(
        `SELECT p.id FROM app.patients p JOIN app.clinics cl ON cl.id = p.clinic_id`,
      );
      const counted = await c.query<{ n: string }>('SELECT count(*)::text AS n FROM app.patients');
      const orgs = await c.query('SELECT id FROM app.organizations');
      return { joined: joined.rows.length, counted: counted.rows[0]?.n, orgs: orgs.rows.length };
    });
    expect(out.joined).toBe(2);
    expect(out.counted).toBe('2');
    expect(out.orgs).toBe(1);
  });

  it('cannot read B’s membership rows', async () => {
    const rows = await asUser(fx.userA, async (c) => {
      const r = await c.query('SELECT user_id FROM app.clinic_users');
      return r.rows;
    });
    expect(rows).toHaveLength(1);
  });
});

describe('the context fails closed', () => {
  it('with NO context set, every tenant table returns zero rows', async () => {
    const out = await asNobody(async (c) => ({
      patients: (await c.query('SELECT id FROM app.patients')).rows.length,
      clinics: (await c.query('SELECT id FROM app.clinics')).rows.length,
      orgs: (await c.query('SELECT id FROM app.organizations')).rows.length,
    }));
    expect(out).toEqual({ patients: 0, clinics: 0, orgs: 0 });
  });

  it('with NO context set, writes are rejected', async () => {
    await expect(
      asNobody((c) =>
        c.query(
          `INSERT INTO app.patients (organization_id, clinic_id, full_name, phone)
           VALUES ($1, $2, 'nobody', '+910000000000')`,
          [fx.orgA, fx.clinicA],
        ),
      ),
    ).rejects.toThrow(/row-level security/i);
  });

  it('an authenticated user who is a member of nothing sees nothing', async () => {
    const rows = await asUser(fx.strangerUser, async (c) => {
      const r = await c.query('SELECT id FROM app.patients');
      return r.rows;
    });
    expect(rows).toHaveLength(0);
  });

  it('set_tenant_context rejects a null user id rather than defaulting', async () => {
    await expect(
      asNobody((c) => c.query('SELECT app.set_tenant_context($1)', [null])),
    ).rejects.toThrow();
  });
});

describe('context does not survive the connection', () => {
  it('a recycled pooled connection carries no leftover tenant', async () => {
    // Establish context, return the connection to the pool, then take one out
    // again and query with nothing set. If SET (not SET LOCAL) had been used, or
    // if the transaction had not been closed, A's rows would appear here.
    await asUser(fx.userA, async (c) => {
      const r = await c.query('SELECT id FROM app.patients');
      expect(r.rows).toHaveLength(2);
    });

    for (let i = 0; i < 6; i += 1) {
      const leaked = await asNobody(async (c) => {
        const r = await c.query('SELECT id FROM app.patients');
        return r.rows.length;
      });
      expect(leaked, `iteration ${i}`).toBe(0);
    }
  });

  it('switching tenant on the same pool never blends the two', async () => {
    const a = await asUser(fx.userA, async (c) =>
      (await c.query<{ id: string }>('SELECT id FROM app.patients')).rows.map((r) => r.id),
    );
    const b = await asUser(fx.userB, async (c) =>
      (await c.query<{ id: string }>('SELECT id FROM app.patients')).rows.map((r) => r.id),
    );
    expect([...a].sort()).toEqual([fx.patientA, fx.patientA2].sort());
    expect(b).toEqual([fx.patientB]);
    // The point of the assertion: no id from one tenant appears in the other.
    expect(a).not.toContain(fx.patientB);
    expect(b).not.toContain(fx.patientA);
  });
});

describe('platform administration is separate and explicit', () => {
  // This block previously asserted the OPPOSITE: that a platform admin coming
  // through the ordinary door crossed every tenant. That was the defect, not the
  // feature, and the heading made it read like a control. Elevation is now
  // something you ask for (migration 0005).
  //
  // These tests call the REAL withTenant/withPlatformAdmin rather than the
  // asUser() mirror above, because the mirror proves things about the migrations
  // and nothing about the code that ships.

  it('an admin using the ordinary door gets their OWN tenants only', async () => {
    const rows = await withTenant(fx.adminUser, async (tx) => {
      const r = await tx.query<{ id: string }>(sql`SELECT id FROM app.patients`);
      return r.rows.map((x) => x.id);
    });
    // adminUser is a member of no clinic, so unelevated they see nothing at all.
    expect(rows).toEqual([]);
  });

  it('crossing tenants requires withPlatformAdmin', async () => {
    const rows = await withPlatformAdmin(fx.adminUser, 'support ticket 4711', async (tx) => {
      const r = await tx.query<{ id: string }>(sql`SELECT id FROM app.patients`);
      return r.rows.map((x) => x.id);
    });
    expect([...rows].sort()).toEqual([fx.patientA, fx.patientA2, fx.patientB].sort());
  });

  it('the elevation is recorded, with its reason, before anything is read', async () => {
    await withPlatformAdmin(fx.adminUser, 'investigating duplicate invoice', async (tx) => {
      await tx.query(sql`SELECT id FROM app.patients`);
    });
    const ev = await owner.query<{ payload: { admin_user_id: string; reason: string } }>(
      `SELECT payload FROM app.system_events
        WHERE event_type = 'platform_admin.elevated'
        ORDER BY occurred_at DESC LIMIT 1`,
    );
    expect(ev.rows[0]?.payload.reason).toBe('investigating duplicate invoice');
    expect(ev.rows[0]?.payload.admin_user_id).toBe(fx.adminUser);
  });

  it('a rolled-back elevation leaves no record of access that never happened', async () => {
    const before = await owner.query<{ n: string }>(
      `SELECT count(*)::text AS n FROM app.system_events WHERE event_type = 'platform_admin.elevated'`,
    );
    await expect(
      withPlatformAdmin(fx.adminUser, 'will fail', async (tx) => {
        await tx.query(sql`SELECT id FROM app.patients`);
        throw new Error('deliberate');
      }),
    ).rejects.toThrow('deliberate');
    const after = await owner.query<{ n: string }>(
      `SELECT count(*)::text AS n FROM app.system_events WHERE event_type = 'platform_admin.elevated'`,
    );
    expect(after.rows[0]?.n).toBe(before.rows[0]?.n);
  });

  it('a non-admin asking to elevate is refused loudly, not downgraded silently', async () => {
    // A silent downgrade would hand the caller zero rows and let it conclude the
    // data is missing rather than that it lacked permission.
    await expect(
      withPlatformAdmin(fx.userA, 'trying it on', async (tx) => {
        await tx.query(sql`SELECT 1`);
      }),
    ).rejects.toThrow(/not an active platform admin/i);
  });

  it('an expired grant cannot elevate', async () => {
    await owner.query(
      `UPDATE app.platform_admins SET expires_at = now() - interval '1 day' WHERE user_id = $1`,
      [fx.adminUser],
    );
    try {
      await expect(
        withPlatformAdmin(fx.adminUser, 'after hours', async (tx) => {
          await tx.query(sql`SELECT 1`);
        }),
      ).rejects.toThrow(/not an active platform admin/i);
    } finally {
      await owner.query(`UPDATE app.platform_admins SET expires_at = NULL WHERE user_id = $1`, [
        fx.adminUser,
      ]);
    }
  });

  it('withPlatformAdmin still refuses an empty reason', async () => {
    await expect(
      withPlatformAdmin(fx.adminUser, '   ', async (tx) => {
        await tx.query(sql`SELECT 1`);
      }),
    ).rejects.toThrow(/requires a reason/i);
  });

  it('a clinic user cannot read the platform_admins table', async () => {
    const rows = await asUser(fx.userA, async (c) => {
      const r = await c.query('SELECT user_id FROM app.platform_admins');
      return r.rows;
    });
    expect(rows).toHaveLength(0);
  });

  it('a clinic user cannot grant themselves platform administration', async () => {
    await expect(
      asUser(fx.userA, (c) =>
        c.query('INSERT INTO app.platform_admins (user_id) VALUES ($1)', [fx.userA]),
      ),
    ).rejects.toThrow(/row-level security/i);
  });

  it('a clinic user cannot widen their own membership', async () => {
    await expect(
      asUser(fx.userA, (c) =>
        c.query(
          `INSERT INTO app.clinic_users (user_id, organization_id, clinic_id, role)
           VALUES ($1, $2, $3, 'clinic_owner')`,
          [fx.userA, fx.orgB, fx.clinicB],
        ),
      ),
    ).rejects.toThrow(/row-level security/i);
  });
});
