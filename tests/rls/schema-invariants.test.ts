import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Client } from 'pg';
import { ownerClient } from '../helpers/db';

/**
 * Structural invariants, asserted against pg_catalog rather than a list.
 *
 * These exist because the biggest finding in M1 — that foreign key validation
 * bypasses RLS, so all 51 single-column FKs to tenant-owned parents were
 * cross-tenant holes — was fixed once and then had nothing guarding it. The
 * first table added in M5-M13 with `patient_id uuid REFERENCES app.patients (id)`
 * would silently reopen the whole class, and CI would be green.
 *
 * Written as catalog queries so they cover tables that do not exist yet.
 */

let owner: Client;

/**
 * Composite (organization_id, <parent_id>) foreign keys present after migration
 * 0004. Raise this when new ones land; lowering it means a tenant relationship
 * was removed, which needs a reason in the commit message.
 */
const COMPOSITE_FK_BASELINE = 67;

beforeAll(async () => {
  owner = ownerClient();
  await owner.connect();
});

afterAll(async () => {
  await owner?.end();
});

describe('cross-tenant references are unrepresentable', () => {
  it('every FK to a tenant-owned parent includes the child organization_id', async () => {
    // FK validation runs with the constraint's own privileges and does NOT pass
    // through RLS. A single-column FK to a tenant-owned parent therefore lets
    // clinic A reference clinic B's row: RLS accepts the row (its own
    // organization_id is A's) and the FK accepts the reference. It is also an
    // existence oracle — a valid id succeeds and an invalid one raises, which
    // reveals whether a given uuid exists in another tenant without reading it.
    //
    // The fix is the composite key: parent carries UNIQUE (organization_id, id),
    // child references the pair, and a cross-tenant reference simply does not
    // exist to be made.
    const res = await owner.query<{ conname: string; child: string; parent: string }>(
      `SELECT con.conname, src.relname AS child, tgt.relname AS parent
         FROM pg_constraint con
         JOIN pg_class src ON src.oid = con.conrelid
         JOIN pg_class tgt ON tgt.oid = con.confrelid
         JOIN pg_namespace n ON n.oid = src.relnamespace
        WHERE n.nspname = 'app'
          AND con.contype = 'f'
          -- the parent is tenant-owned
          AND EXISTS (SELECT 1 FROM pg_attribute a
                       WHERE a.attrelid = tgt.oid AND a.attname = 'organization_id'
                         AND NOT a.attisdropped)
          -- and so is the child
          AND EXISTS (SELECT 1 FROM pg_attribute a
                       WHERE a.attrelid = src.oid AND a.attname = 'organization_id'
                         AND NOT a.attisdropped)
          -- but the constraint does not carry the child's organization_id
          AND NOT EXISTS (SELECT 1 FROM pg_attribute a
                           WHERE a.attrelid = src.oid AND a.attname = 'organization_id'
                             AND NOT a.attisdropped
                             AND a.attnum = ANY (con.conkey))
        ORDER BY child, conname`,
    );
    const offenders = res.rows.map((r) => `${r.child} -> ${r.parent} (${r.conname})`);
    expect(offenders).toEqual([]);
  });

  it('the number of composite tenant FKs never falls below the M1 baseline', () => {
    // A ratchet, not a snapshot.
    //
    // The obvious companion assertion — "every tenant parent carries
    // UNIQUE (organization_id, id)" — turns out to be tautological: Postgres
    // will not create a composite FK without a matching unique constraint, so it
    // cannot fail independently. Worse, scoping it to "tables that are currently
    // referenced" is circular, because dropping the key with CASCADE also drops
    // the referencing FKs and the table quietly stops qualifying.
    //
    // This catches the case the first test cannot: a tenant relationship removed
    // outright rather than weakened. Raise BASELINE when new composite FKs land;
    // never lower it without saying why in the commit message.
    expect(COMPOSITE_FK_BASELINE).toBe(67);
  });

  it('composite tenant FKs are at or above the baseline', async () => {
    const res = await owner.query<{ n: string }>(
      `SELECT count(*)::text AS n
         FROM pg_constraint con
         JOIN pg_class src ON src.oid = con.conrelid
         JOIN pg_class tgt ON tgt.oid = con.confrelid
         JOIN pg_namespace n ON n.oid = src.relnamespace
        WHERE n.nspname = 'app' AND con.contype = 'f'
          AND EXISTS (SELECT 1 FROM pg_attribute a
                       WHERE a.attrelid = tgt.oid AND a.attname = 'organization_id'
                         AND NOT a.attisdropped)
          AND EXISTS (SELECT 1 FROM pg_attribute a
                       WHERE a.attrelid = src.oid AND a.attname = 'organization_id'
                         AND NOT a.attisdropped
                         AND a.attnum = ANY (con.conkey))`,
    );
    expect(Number(res.rows[0]?.n)).toBeGreaterThanOrEqual(COMPOSITE_FK_BASELINE);
  });

  it('the invariant covers a meaningful number of constraints, not zero', async () => {
    // Guards against the check passing because the pattern matches nothing —
    // a rewritten catalog query that silently selects no rows would otherwise
    // look identical to a clean schema.
    const res = await owner.query<{ n: string }>(
      `SELECT count(*)::text AS n
         FROM pg_constraint con
         JOIN pg_class src ON src.oid = con.conrelid
         JOIN pg_class tgt ON tgt.oid = con.confrelid
         JOIN pg_namespace n ON n.oid = src.relnamespace
        WHERE n.nspname = 'app' AND con.contype = 'f'
          AND EXISTS (SELECT 1 FROM pg_attribute a
                       WHERE a.attrelid = tgt.oid AND a.attname = 'organization_id'
                         AND NOT a.attisdropped)`,
    );
    expect(Number(res.rows[0]?.n)).toBeGreaterThan(40);
  });
});

describe('clinic_id is constrained, not merely conventional', () => {
  it('every table carrying clinic_id references app.clinics', async () => {
    // Twenty tables carried clinic_id with no FK at all, so it could hold any
    // uuid including another organization's clinic. RLS never caught it because
    // every policy keys on organization_id. Open decision 5 called multi-location
    // UI "a flag flip"; it could not have been.
    const res = await owner.query<{ relname: string }>(
      `SELECT c.relname
         FROM pg_class c
         JOIN pg_namespace n ON n.oid = c.relnamespace
         JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'clinic_id'
                            AND NOT a.attisdropped
        WHERE n.nspname = 'app' AND c.relkind = 'r'
          AND NOT EXISTS (
            SELECT 1 FROM pg_constraint fk
              JOIN pg_class t ON t.oid = fk.confrelid
             WHERE fk.conrelid = c.oid AND fk.contype = 'f' AND t.relname = 'clinics'
          )
        ORDER BY c.relname`,
    );
    expect(res.rows.map((r) => r.relname)).toEqual([]);
  });

  it('those references are composite, so a foreign clinic is unrepresentable', async () => {
    const res = await owner.query<{ relname: string; conname: string }>(
      `SELECT src.relname, con.conname
         FROM pg_constraint con
         JOIN pg_class src ON src.oid = con.conrelid
         JOIN pg_class tgt ON tgt.oid = con.confrelid
         JOIN pg_namespace n ON n.oid = src.relnamespace
        WHERE n.nspname = 'app' AND con.contype = 'f' AND tgt.relname = 'clinics'
          AND array_length(con.conkey, 1) < 2
        ORDER BY src.relname`,
    );
    expect(res.rows.map((r) => `${r.relname}.${r.conname}`)).toEqual([]);
  });
});

describe('RLS coverage holds as the schema grows', () => {
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

  it('append-only tables have no UPDATE or DELETE policy', async () => {
    // audit_logs, access_logs, usage_events and error_events were given FOR ALL
    // in 0002, so the tenant being audited could rewrite its own trail. Fixed in
    // 0003; this stops a later migration handing them one back.
    const res = await owner.query<{ relname: string; polname: string; polcmd: string }>(
      `SELECT c.relname, p.polname, p.polcmd
         FROM pg_policy p
         JOIN pg_class c ON c.oid = p.polrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'app'
          AND c.relname IN ('audit_logs', 'access_logs', 'usage_events', 'error_events')
          AND p.polcmd IN ('w', 'd', '*')
        ORDER BY c.relname, p.polname`,
    );
    const offenders = res.rows.map((r) => `${r.relname}.${r.polname} (cmd=${r.polcmd})`);
    expect(offenders).toEqual([]);
  });
});
