import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Client, Pool, PoolClient } from 'pg';
import { appPool, ownerClient, seed, truncateAll, type Fixture } from '../helpers/db';

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
      return r.rows;
    });
    expect(rows).toHaveLength(1);
    expect(rows[0]?.id).toBe(fx.patientA);
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
    expect(out.joined).toBe(1);
    expect(out.counted).toBe('1');
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
      expect(r.rows).toHaveLength(1);
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
    expect(a).toEqual([fx.patientA]);
    expect(b).toEqual([fx.patientB]);
  });
});

describe('platform administration is separate and explicit', () => {
  it('a platform admin can cross tenants', async () => {
    const rows = await asUser(fx.adminUser, async (c) => {
      const r = await c.query('SELECT id FROM app.patients');
      return r.rows;
    });
    expect(rows).toHaveLength(2);
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
    // The DB derives context from clinic_users, so writing that table would be
    // the way to escalate. The policy on it is what closes the loop.
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
