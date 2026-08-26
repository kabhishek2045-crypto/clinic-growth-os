import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Client, Pool, PoolClient } from 'pg';
import { appPool, ownerClient, seed, truncateAll, type Fixture } from '../helpers/db';

/**
 * The public and patient principals (migration 0004).
 *
 * The security property under test is NEGATIVE and it is the whole point: a
 * public or patient session must reach a small, explicit set of rows and
 * NOTHING else. In particular neither may ever inherit the staff _tenant
 * policies, which is what would happen if either setter populated
 * app.current_org_ids.
 */

let owner: Client;
let pool: Pool;
let fx: Fixture;
let domainA: string;

/**
 * A uuid that cannot collide with a fixture.
 *
 * These two tests previously derived a "missing" id by replacing the last
 * character of a real one with '0' — which returns the ORIGINAL id whenever it
 * already ended in '0'. It passed against Neon and failed against the embedded
 * server purely on how the random uuid landed.
 */
const ABSENT_UUID = '00000000-0000-7000-8000-000000000000';

async function inTx<T>(setup: string | null, args: unknown[], fn: (c: PoolClient) => Promise<T>) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    if (setup) await client.query(setup, args);
    return await fn(client);
  } finally {
    await client.query('ROLLBACK').catch(() => undefined);
    client.release();
  }
}

const asPublic = <T>(orgId: string, fn: (c: PoolClient) => Promise<T>) =>
  inTx('SELECT app.set_public_context($1)', [orgId], fn);
const asPatient = <T>(patientId: string, fn: (c: PoolClient) => Promise<T>) =>
  inTx('SELECT app.set_patient_context($1)', [patientId], fn);
const asStaff = <T>(userId: string, fn: (c: PoolClient) => Promise<T>) =>
  inTx('SELECT app.set_tenant_context($1)', [userId], fn);
const asNobody = <T>(fn: (c: PoolClient) => Promise<T>) => inTx(null, [], fn);

beforeAll(async () => {
  owner = ownerClient();
  await owner.connect();
  await truncateAll(owner);
  fx = await seed(owner);

  const d = await owner.query<{ id: string }>(
    `INSERT INTO app.clinic_domains
       (organization_id, clinic_id, domain, normalized_domain, domain_type, status)
     VALUES ($1, $2, 'abc.example.com', 'abc.example.com', 'custom', 'active') RETURNING id`,
    [fx.orgA, fx.clinicA],
  );
  domainA = d.rows[0]?.id as string;

  await owner.query(
    `INSERT INTO app.clinic_domains
       (organization_id, clinic_id, domain, normalized_domain, domain_type, status)
     VALUES ($1, $2, 'pending.example.com', 'pending.example.com', 'custom', 'pending')`,
    [fx.orgA, fx.clinicA],
  );
  await owner.query(
    `INSERT INTO app.websites (organization_id, clinic_id, status) VALUES ($1, $2, 'published')`,
    [fx.orgA, fx.clinicA],
  );
  pool = appPool();
});

afterAll(async () => {
  await pool?.end();
  await owner?.end();
});

describe('domain resolution works before any principal exists', () => {
  it('resolves a live domain with no context set', async () => {
    const rows = await asNobody(
      async (c) =>
        (
          await c.query<{ organization_id: string }>('SELECT * FROM app.resolve_domain($1)', [
            'abc.example.com',
          ])
        ).rows,
    );
    expect(rows).toHaveLength(1);
    expect(rows[0]?.organization_id).toBe(fx.orgA);
    expect(domainA).toBeTruthy();
  });

  it('normalises case and surrounding whitespace', async () => {
    const rows = await asNobody(
      async (c) =>
        (await c.query('SELECT * FROM app.resolve_domain($1)', ['  ABC.Example.COM  '])).rows,
    );
    expect(rows).toHaveLength(1);
  });

  it('returns nothing for a pending domain, and nothing for an unknown one', async () => {
    const pending = await asNobody(
      async (c) =>
        (await c.query('SELECT * FROM app.resolve_domain($1)', ['pending.example.com'])).rows,
    );
    const unknown = await asNobody(
      async (c) =>
        (await c.query('SELECT * FROM app.resolve_domain($1)', ['evil.example.com'])).rows,
    );
    // Indistinguishable to the caller: no enumeration oracle.
    expect(pending).toHaveLength(0);
    expect(unknown).toHaveLength(0);
  });

  it('still exposes no general read of clinic_domains', async () => {
    const rows = await asNobody(
      async (c) => (await c.query('SELECT id FROM app.clinic_domains')).rows,
    );
    expect(rows).toHaveLength(0);
  });
});

describe('the public principal reaches the public face and nothing else', () => {
  it('reads the clinic, its doctors, services and website', async () => {
    const out = await asPublic(fx.orgA, async (c) => ({
      clinics: (await c.query('SELECT id FROM app.clinics')).rows.length,
      doctors: (await c.query('SELECT id FROM app.doctors')).rows.length,
      websites: (await c.query('SELECT id FROM app.websites')).rows.length,
    }));
    expect(out.clinics).toBe(1);
    expect(out.doctors).toBe(1);
    expect(out.websites).toBe(1);
  });

  it('CANNOT read patients, appointments, invoices or prescriptions', async () => {
    const out = await asPublic(fx.orgA, async (c) => ({
      patients: (await c.query('SELECT id FROM app.patients')).rows.length,
      appointments: (await c.query('SELECT id FROM app.appointments')).rows.length,
      invoices: (await c.query('SELECT id FROM app.invoices')).rows.length,
      conditions: (await c.query('SELECT id FROM app.health_conditions')).rows.length,
      households: (await c.query('SELECT id FROM app.households')).rows.length,
    }));
    expect(out).toEqual({
      patients: 0,
      appointments: 0,
      invoices: 0,
      conditions: 0,
      households: 0,
    });
  });

  it("CANNOT read another organization's public face", async () => {
    const n = await asPublic(
      fx.orgA,
      async (c) =>
        (await c.query('SELECT id FROM app.clinics WHERE organization_id = $1', [fx.orgB])).rows
          .length,
    );
    expect(n).toBe(0);
  });

  it('can create a lead, stamped with the resolved organization', async () => {
    const n = await asPublic(fx.orgA, async (c) => {
      const r = await c.query(
        `INSERT INTO app.leads (organization_id, clinic_id, full_name, phone, consent_given)
         VALUES ($1, $2, 'Walk-in enquiry', '+919111111111', true)`,
        [fx.orgA, fx.clinicA],
      );
      return r.rowCount;
    });
    expect(n).toBe(1);
  });

  it('CANNOT create a lead in another organization', async () => {
    await expect(
      asPublic(fx.orgA, (c) =>
        c.query(
          `INSERT INTO app.leads (organization_id, clinic_id, full_name, phone)
           VALUES ($1, $2, 'planted', '+919222222222')`,
          [fx.orgB, fx.clinicB],
        ),
      ),
    ).rejects.toThrow(/row-level security/i);
  });

  it('cannot read back the leads it created', async () => {
    // Write-only by design: a visitor may create an enquiry and may not enumerate
    // anyone's, including their own.
    const n = await asPublic(fx.orgA, async (c) => {
      await c.query(
        `INSERT INTO app.leads (organization_id, clinic_id, full_name, phone)
         VALUES ($1, $2, 'mine', '+919333333333')`,
        [fx.orgA, fx.clinicA],
      );
      return (await c.query('SELECT id FROM app.leads')).rows.length;
    });
    expect(n).toBe(0);
  });

  it('is refused for an unknown organization', async () => {
    await expect(
      asNobody((c) => c.query('SELECT app.set_public_context($1)', [ABSENT_UUID])),
    ).rejects.toThrow();
  });
});

describe('the patient principal reaches only its own records', () => {
  it('reads its own patient row and ONLY its own conditions', async () => {
    // patientA2 is in the same organization and has their own condition, so this
    // discriminates between a policy scoped by patient and one scoped by org.
    const out = await asPatient(fx.patientA, async (c) => ({
      me: (await c.query<{ id: string }>('SELECT id FROM app.patients')).rows.map((r) => r.id),
      conditions: (await c.query<{ id: string }>('SELECT id FROM app.health_conditions')).rows.map(
        (r) => r.id,
      ),
    }));
    expect(out.me).toEqual([fx.patientA]);
    expect(out.conditions).toEqual([fx.conditionA]);
    expect(out.conditions).not.toContain(fx.conditionA2);
  });

  it("CANNOT read a same-org patient's clinical records", async () => {
    const n = await asPatient(
      fx.patientA,
      async (c) =>
        (
          await c.query('SELECT id FROM app.health_conditions WHERE patient_id = $1', [
            fx.patientA2,
          ])
        ).rows.length,
    );
    expect(n).toBe(0);
  });

  it('CANNOT read a household member — a household is not a security boundary', async () => {
    // §6 is explicit. patientA2 shares householdA with patientA.
    const out = await asPatient(fx.patientA, async (c) => ({
      others: (await c.query('SELECT id FROM app.patients WHERE id = $1', [fx.patientA2])).rows
        .length,
      households: (await c.query('SELECT id FROM app.households')).rows.length,
      links: (await c.query('SELECT id FROM app.patient_household_links')).rows.length,
    }));
    expect(out).toEqual({ others: 0, households: 0, links: 0 });
  });

  it("CANNOT read another tenant's patient", async () => {
    const n = await asPatient(
      fx.patientA,
      async (c) =>
        (await c.query('SELECT id FROM app.patients WHERE id = $1', [fx.patientB])).rows.length,
    );
    expect(n).toBe(0);
  });

  it('CANNOT read staff-only tables', async () => {
    const out = await asPatient(fx.patientA, async (c) => ({
      users: (await c.query('SELECT id FROM app.clinic_users')).rows.length,
      audit: (await c.query('SELECT id FROM app.audit_logs')).rows.length,
      leads: (await c.query('SELECT id FROM app.leads')).rows.length,
    }));
    expect(out).toEqual({ users: 0, audit: 0, leads: 0 });
  });

  it('cannot write to its own clinical record', async () => {
    const n = await asPatient(fx.patientA, async (c) => {
      const r = await c.query(`UPDATE app.patients SET full_name = 'renamed'`);
      return r.rowCount;
    });
    expect(n).toBe(0);
  });

  it('is refused for an unknown patient', async () => {
    await expect(
      asNobody((c) =>
        c.query('SELECT app.set_patient_context($1)', [fx.patientB.replace(/.$/, '0')]),
      ),
    ).rejects.toThrow();
  });
});

describe('principals are mutually exclusive', () => {
  const pairs: [string, string, unknown[]][] = [
    ['staff then public', 'SELECT app.set_public_context($1)', []],
    ['staff then patient', 'SELECT app.set_patient_context($1)', []],
  ];

  it('a public context cannot be layered onto a staff one', async () => {
    await expect(
      asStaff(fx.userA, (c) => c.query('SELECT app.set_public_context($1)', [fx.orgA])),
    ).rejects.toThrow(/already set/i);
    expect(pairs.length).toBe(2);
  });

  it('a patient context cannot be layered onto a staff one', async () => {
    await expect(
      asStaff(fx.userA, (c) => c.query('SELECT app.set_patient_context($1)', [fx.patientA])),
    ).rejects.toThrow(/already set/i);
  });

  it('a staff context cannot be layered onto a public one', async () => {
    await expect(
      asPublic(fx.orgA, (c) => c.query('SELECT app.set_tenant_context($1)', [fx.userA])),
    ).rejects.toThrow(/already set/i);
  });

  it('a staff context cannot be layered onto a patient one', async () => {
    await expect(
      asPatient(fx.patientA, (c) => c.query('SELECT app.set_tenant_context($1)', [fx.userA])),
    ).rejects.toThrow(/already set/i);
  });
});

describe('the new principals do not weaken the staff boundary', () => {
  it('a public session has no staff org ids', async () => {
    const out = await asPublic(fx.orgA, async (c) => {
      const r = await c.query<{ orgs: string[]; principal: string }>(
        'SELECT app.current_org_ids() AS orgs, app.current_principal() AS principal',
      );
      return r.rows[0];
    });
    expect(out?.orgs).toEqual([]);
    expect(out?.principal).toBe('public');
  });

  it('a patient session has no staff org ids', async () => {
    const out = await asPatient(fx.patientA, async (c) => {
      const r = await c.query<{ orgs: string[]; principal: string }>(
        'SELECT app.current_org_ids() AS orgs, app.current_principal() AS principal',
      );
      return r.rows[0];
    });
    expect(out?.orgs).toEqual([]);
    expect(out?.principal).toBe('patient');
  });

  it('staff isolation is unchanged', async () => {
    const rows = await asStaff(fx.userA, async (c) =>
      (await c.query<{ id: string }>('SELECT id FROM app.patients')).rows.map((r) => r.id),
    );
    expect([...rows].sort()).toEqual([fx.patientA, fx.patientA2].sort());
  });
});
