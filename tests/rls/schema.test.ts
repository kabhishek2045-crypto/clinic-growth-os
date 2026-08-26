import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import type { Client, Pool, PoolClient } from 'pg';
import { appPool, ownerClient, seed, truncateAll, type Fixture } from '../helpers/db';

/**
 * Schema-wide invariants and the Family Health Graph.
 *
 * The coverage assertions here are the ones that matter most as the schema
 * grows: they are written against pg_catalog rather than a list, so a table
 * added in a later migration without a policy fails the build instead of
 * shipping unprotected.
 */

let owner: Client;
let pool: Pool;
let fx: Fixture;

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

describe('schema-wide coverage', () => {
  it('every table in the app schema has RLS enabled AND forced', async () => {
    const res = await owner.query<{ relname: string }>(
      `SELECT c.relname
         FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'app' AND c.relkind = 'r'
          AND NOT (c.relrowsecurity AND c.relforcerowsecurity)`,
    );
    expect(res.rows.map((r) => r.relname)).toEqual([]);
  });

  it('every table in the app schema has at least one policy', async () => {
    const res = await owner.query<{ relname: string }>(
      `SELECT c.relname
         FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'app' AND c.relkind = 'r'
          AND NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid)`,
    );
    expect(res.rows.map((r) => r.relname)).toEqual([]);
  });

  it('every tenant table carries organization_id', async () => {
    // The policies key on organization_id. A tenant table without the column
    // could not have been given the standard policy, so this catches a table
    // that was added to the wrong list in migration 0002.
    const res = await owner.query<{ relname: string }>(
      `SELECT c.relname
         FROM pg_class c
         JOIN pg_namespace n ON n.oid = c.relnamespace
         JOIN pg_policy p ON p.polrelid = c.oid
        WHERE n.nspname = 'app' AND c.relkind = 'r'
          AND p.polname LIKE '%_tenant'
          -- organizations is the one exception by construction: it IS the tenant,
          -- so its policy keys on id rather than on an organization_id column.
          AND c.relname <> 'organizations'
          AND NOT EXISTS (
            SELECT 1 FROM pg_attribute a
             WHERE a.attrelid = c.oid AND a.attname = 'organization_id' AND NOT a.attisdropped
          )`,
    );
    expect(res.rows.map((r) => r.relname)).toEqual([]);
  });

  it('uuid_v7 emits version 7', async () => {
    const res = await owner.query<{ ids: string[] }>(
      `SELECT array_agg(app.uuid_v7()::text) AS ids FROM generate_series(1, 50) i`,
    );
    const ids = res.rows[0]?.ids ?? [];
    expect(ids).toHaveLength(50);
    for (const id of ids) expect(id[14]).toBe('7');
    expect(new Set(ids).size).toBe(50);
  });

  it('uuid_v7 sorts in creation order across milliseconds', async () => {
    // The timestamp is millisecond-granular, so ids minted inside a single
    // millisecond are ordered only by their random tail. The property that
    // matters for index locality is that LATER means GREATER, so this samples
    // across real elapsed time -- in separate round trips, because pg_sleep in a
    // cross join is evaluated once and every row still lands in one millisecond.
    const ids: string[] = [];
    for (let i = 0; i < 6; i += 1) {
      const res = await owner.query<{ id: string }>(`SELECT app.uuid_v7()::text AS id`);
      ids.push(res.rows[0]?.id as string);
      await new Promise((r) => setTimeout(r, 5));
    }
    expect(ids).toEqual([...ids].sort());
  });
});

describe('the platform catalogue is readable but not writable by a clinic', () => {
  it('a clinic user can read roles and permissions', async () => {
    const out = await asUser(fx.userA, async (c) => ({
      roles: (await c.query('SELECT key FROM app.roles')).rows.length,
      perms: (await c.query('SELECT key FROM app.permissions')).rows.length,
      plans: (await c.query('SELECT key FROM app.plans')).rows.length,
    }));
    expect(out.roles).toBeGreaterThan(0);
    expect(out.perms).toBeGreaterThan(0);
    expect(out.plans).toBeGreaterThan(0);
  });

  it('a clinic user cannot invent a permission', async () => {
    await expect(
      asUser(fx.userA, (c) =>
        c.query(`INSERT INTO app.permissions (key, description) VALUES ('everything.always', 'x')`),
      ),
    ).rejects.toThrow(/row-level security/i);
  });

  it('a clinic user cannot grant a permission to a role', async () => {
    await expect(
      asUser(fx.userA, (c) =>
        c.query(
          `INSERT INTO app.role_permissions (role_key, permission_key)
           VALUES ('read_only_staff', 'billing.refund')`,
        ),
      ),
    ).rejects.toThrow(/row-level security/i);
  });

  it('a clinic user cannot rewrite a plan', async () => {
    const n = await asUser(fx.userA, async (c) => {
      const r = await c.query(`UPDATE app.plans SET price_minor = 0`);
      return r.rowCount;
    });
    expect(n).toBe(0);
  });
});

describe('Family Health Graph is tenant-scoped like everything else', () => {
  it('a clinic sees only its own households', async () => {
    const rows = await asUser(fx.userA, async (c) =>
      (await c.query<{ id: string }>('SELECT id FROM app.households')).rows.map((r) => r.id),
    );
    expect(rows).toEqual([fx.householdA]);
  });

  it("cannot read another clinic's health conditions", async () => {
    const rows = await asUser(
      fx.userA,
      async (c) =>
        (await c.query('SELECT id FROM app.health_conditions WHERE id = $1', [fx.conditionB])).rows,
    );
    expect(rows).toHaveLength(0);
  });

  it("cannot link its own patient into another clinic's household", async () => {
    await expect(
      asUser(fx.userA, (c) =>
        c.query(
          `INSERT INTO app.patient_household_links (organization_id, patient_id, household_id, relationship)
           VALUES ($1, $2, $3, 'dependent')`,
          [fx.orgA, fx.patientA, fx.householdB],
        ),
      ),
    ).rejects.toThrow();
  });

  it('a household groups patients without granting access between them', async () => {
    // §6 — "a household is a grouping construct, never a security boundary."
    // Membership must not widen what a session can read; the tenant policy is
    // still the only thing that decides.
    const members = await asUser(fx.userA, async (c) =>
      (
        await c.query<{ patient_id: string }>(
          `SELECT phl.patient_id
             FROM app.patient_household_links phl
            WHERE phl.household_id = $1`,
          [fx.householdA],
        )
      ).rows.map((r) => r.patient_id),
    );
    expect(members.sort()).toEqual([fx.patientA, fx.patientA2].sort());

    // The same query from the other tenant returns nothing, even given the id.
    const leaked = await asUser(
      fx.userB,
      async (c) =>
        (
          await c.query(
            `SELECT patient_id FROM app.patient_household_links WHERE household_id = $1`,
            [fx.householdA],
          )
        ).rows,
    );
    expect(leaked).toHaveLength(0);
  });

  it('condition-tagged timeline events resolve within a tenant and nowhere else', async () => {
    // §17 — "everything related to this patient's diabetes", which is the query
    // the whole graph exists to make possible.
    const eventId = await asUser(fx.userA, async (c) => {
      const ev = await c.query<{ id: string }>(
        `INSERT INTO app.patient_timeline_events
           (organization_id, clinic_id, patient_id, event_type, summary)
         VALUES ($1, $2, $3, 'appointment_completed', 'Quarterly diabetic review')
         RETURNING id`,
        [fx.orgA, fx.clinicA, fx.patientA],
      );
      const id = ev.rows[0]?.id as string;
      await c.query(
        `INSERT INTO app.condition_timeline_events
           (organization_id, health_condition_id, timeline_event_id)
         VALUES ($1, $2, $3)`,
        [fx.orgA, fx.conditionA, id],
      );
      const joined = await c.query<{ summary: string }>(
        `SELECT e.summary
           FROM app.condition_timeline_events cte
           JOIN app.patient_timeline_events e ON e.id = cte.timeline_event_id
          WHERE cte.health_condition_id = $1`,
        [fx.conditionA],
      );
      expect(joined.rows.map((r) => r.summary)).toEqual(['Quarterly diabetic review']);
      return id;
    });
    expect(eventId).toBeTruthy();
  });
});

describe('double booking is prevented by the database, not by application checks', () => {
  const slot = '2026-09-01T10:00:00+05:30';
  const slotEnd = '2026-09-01T10:30:00+05:30';

  afterEach(async () => {
    await owner.query('DELETE FROM app.appointments');
  });

  it('rejects a genuinely concurrent second booking for the same doctor', async () => {
    // Two real connections, two real overlapping transactions.
    //
    // The previous version of this test opened ONE transaction and did both
    // INSERTs inside it, while its comment claimed the opposite. That never
    // exercised the path M6 will actually hit: under real concurrency the second
    // inserter BLOCKS on the exclusion constraint until the first transaction
    // resolves, and only then succeeds or fails. Blocking across a network round
    // trip inside a request handler is the behaviour that matters.
    const a = await pool.connect();
    const b = await pool.connect();
    try {
      await a.query('BEGIN');
      await a.query('SELECT app.set_tenant_context($1)', [fx.userA]);
      await b.query('BEGIN');
      await b.query('SELECT app.set_tenant_context($1)', [fx.userA]);

      await a.query(
        `INSERT INTO app.appointments
           (organization_id, clinic_id, patient_id, doctor_id, starts_at, ends_at, status)
         VALUES ($1, $2, $3, $4, $5, $6, 'booked')`,
        [fx.orgA, fx.clinicA, fx.patientA, fx.doctorA, slot, slotEnd],
      );

      // Deliberately NOT awaited: this blocks on A's lock until A resolves.
      const bInsert = b.query(
        `INSERT INTO app.appointments
           (organization_id, clinic_id, patient_id, doctor_id, starts_at, ends_at, status)
         VALUES ($1, $2, $3, $4, $5, $6, 'booked')`,
        [fx.orgA, fx.clinicA, fx.patientA2, fx.doctorA, '2026-09-01T10:15:00+05:30', slotEnd],
      );

      await a.query('COMMIT');

      await expect(bInsert).rejects.toThrow(
        /appointments_no_double_booking|conflicting key|exclusion/i,
      );
      await b.query('ROLLBACK');
    } finally {
      a.release();
      b.release();
    }
  });

  it('frees the slot when an existing booking is actually cancelled', async () => {
    // The previous version inserted a row that was ALREADY 'cancelled', so it
    // never exercised the partial-index predicate transition it claimed to test.
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT app.set_tenant_context($1)', [fx.userA]);

      const first = await client.query<{ id: string }>(
        `INSERT INTO app.appointments
           (organization_id, clinic_id, patient_id, doctor_id, starts_at, ends_at, status)
         VALUES ($1, $2, $3, $4, $5, $6, 'booked') RETURNING id`,
        [fx.orgA, fx.clinicA, fx.patientA, fx.doctorA, slot, slotEnd],
      );

      // Same slot while the first is still live: must be refused.
      await expect(
        client.query(
          `INSERT INTO app.appointments
             (organization_id, clinic_id, patient_id, doctor_id, starts_at, ends_at, status)
           VALUES ($1, $2, $3, $4, $5, $6, 'booked')`,
          [fx.orgA, fx.clinicA, fx.patientA2, fx.doctorA, slot, slotEnd],
        ),
      ).rejects.toThrow(/appointments_no_double_booking|conflicting key|exclusion/i);

      await client.query('ROLLBACK');

      // Now cancel it for real, and the slot must become bookable.
      await client.query('BEGIN');
      await client.query('SELECT app.set_tenant_context($1)', [fx.userA]);
      await client.query(
        `INSERT INTO app.appointments
           (organization_id, clinic_id, patient_id, doctor_id, starts_at, ends_at, status)
         VALUES ($1, $2, $3, $4, $5, $6, 'booked')`,
        [fx.orgA, fx.clinicA, fx.patientA, fx.doctorA, slot, slotEnd],
      );
      await client.query(`UPDATE app.appointments SET status = 'cancelled'`);
      const replacement = await client.query(
        `INSERT INTO app.appointments
           (organization_id, clinic_id, patient_id, doctor_id, starts_at, ends_at, status)
         VALUES ($1, $2, $3, $4, $5, $6, 'booked') RETURNING id`,
        [fx.orgA, fx.clinicA, fx.patientA2, fx.doctorA, slot, slotEnd],
      );
      expect(replacement.rowCount).toBe(1);
      expect(first.rowCount).toBe(1);
      await client.query('ROLLBACK');
    } finally {
      client.release();
    }
  });
});

describe('append-only tables cannot be rewritten by the tenant they audit', () => {
  it('a clinic user can write and read its own audit entries', async () => {
    const n = await asUser(fx.userA, async (c) => {
      await c.query(
        `INSERT INTO app.audit_logs (organization_id, action, entity_type)
         VALUES ($1, 'patient.updated', 'patient')`,
        [fx.orgA],
      );
      const r = await c.query('SELECT id FROM app.audit_logs');
      return r.rows.length;
    });
    expect(n).toBe(1);
  });

  it('cannot DELETE its own audit trail', async () => {
    await asUser(fx.userA, async (c) => {
      await c.query(
        `INSERT INTO app.audit_logs (organization_id, action, entity_type)
         VALUES ($1, 'invoice.deleted', 'invoice')`,
        [fx.orgA],
      );
      // No DELETE policy exists, and RLS is forced, so this matches nothing.
      const del = await c.query('DELETE FROM app.audit_logs');
      expect(del.rowCount).toBe(0);
    });
  });

  it('cannot UPDATE an audit entry after the fact', async () => {
    await asUser(fx.userA, async (c) => {
      await c.query(
        `INSERT INTO app.audit_logs (organization_id, action, entity_type)
         VALUES ($1, 'payment.refunded', 'payment')`,
        [fx.orgA],
      );
      const upd = await c.query(`UPDATE app.audit_logs SET action = 'nothing.happened'`);
      expect(upd.rowCount).toBe(0);
    });
  });

  it('the same holds for access_logs and usage_events', async () => {
    await asUser(fx.userA, async (c) => {
      await c.query(
        `INSERT INTO app.access_logs (organization_id, resource_type, action)
         VALUES ($1, 'patient', 'read')`,
        [fx.orgA],
      );
      expect((await c.query('DELETE FROM app.access_logs')).rowCount).toBe(0);

      await c.query(
        `INSERT INTO app.usage_events (organization_id, feature_key, quantity)
         VALUES ($1, 'whatsapp_messages', 1)`,
        [fx.orgA],
      );
      expect((await c.query('DELETE FROM app.usage_events')).rowCount).toBe(0);
    });
  });
});

describe('errors are loggable even when there is no tenant', () => {
  it('an untenanted error can be written', async () => {
    // The failures that most need logging - unknown host, auth failure, pool
    // exhaustion - have no organization_id. Under the old tenant policy
    // NULL = ANY(...) was never TRUE, so none of them could be recorded at all.
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      // No RETURNING: under RLS, INSERT ... RETURNING also requires the new row
      // to pass the SELECT policy, and an untenanted error row is deliberately
      // not readable by a session with no context. The write is what matters.
      const res = await client.query(
        `INSERT INTO app.error_events (organization_id, level, message)
         VALUES (NULL, 'error', 'unknown host: evil.example.com')`,
      );
      expect(res.rowCount).toBe(1);
      await client.query('ROLLBACK');
    } finally {
      client.release();
    }
  });

  it('a tenanted error is written and readable by its own tenant', async () => {
    const n = await asUser(fx.userA, async (c) => {
      await c.query(
        `INSERT INTO app.error_events (organization_id, level, message)
         VALUES ($1, 'error', 'pool exhausted')`,
        [fx.orgA],
      );
      return (await c.query('SELECT id FROM app.error_events')).rows.length;
    });
    expect(n).toBe(1);
  });

  it('an error record cannot be edited or deleted', async () => {
    await asUser(fx.userA, async (c) => {
      await c.query(
        `INSERT INTO app.error_events (organization_id, level, message)
         VALUES ($1, 'fatal', 'keep me')`,
        [fx.orgA],
      );
      expect((await c.query('DELETE FROM app.error_events')).rowCount).toBe(0);
      expect((await c.query(`UPDATE app.error_events SET message = 'x'`)).rowCount).toBe(0);
    });
  });
});
