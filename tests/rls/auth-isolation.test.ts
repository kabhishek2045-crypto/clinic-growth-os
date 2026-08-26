import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Client, Pool } from 'pg';
import { appPool, authClient, ownerClient, seed, truncateAll, type Fixture } from '../helpers/db';

/**
 * The crown jewels are unreachable from the tenant path.
 *
 * Session tokens and password hashes live in app."session" and app."account".
 * The tenant role has no grant on them, so this holds even against total SQL
 * injection in a tenant query — the role running that query cannot name the
 * tables. A policy would not have achieved this: Better Auth reads `user` by
 * email and `session` by token before any principal exists, so a principal-keyed
 * policy would deadlock sign-in.
 */

let owner: Client;
let pool: Pool;
let fx: Fixture;

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

describe('the tenant role cannot reach the auth tables', () => {
  it.each(['user', 'session', 'account', 'verification'])(
    'clinic_os_app is refused on app."%s"',
    async (table) => {
      const c = await pool.connect();
      try {
        await expect(c.query(`SELECT * FROM app."${table}" LIMIT 1`)).rejects.toThrow(
          /permission denied/i,
        );
      } finally {
        c.release();
      }
    },
  );

  it('clinic_os_app holds no privilege on them at all', async () => {
    const res = await owner.query<{ t: string; sel: boolean; ins: boolean }>(
      `SELECT t AS t,
              has_table_privilege('clinic_os_app', 'app.' || quote_ident(t), 'SELECT') AS sel,
              has_table_privilege('clinic_os_app', 'app.' || quote_ident(t), 'INSERT') AS ins
         FROM unnest(ARRAY['user','session','account','verification']) AS t`,
    );
    for (const row of res.rows) {
      expect(row.sel, `${row.t} SELECT`).toBe(false);
      expect(row.ins, `${row.t} INSERT`).toBe(false);
    }
  });

  it('a password hash cannot be read through the tenant role', async () => {
    const c = await pool.connect();
    try {
      await expect(c.query(`SELECT "password" FROM app."account"`)).rejects.toThrow(
        /permission denied/i,
      );
    } finally {
      c.release();
    }
  });
});

describe('the auth role reaches its own tables and nothing else', () => {
  it('clinic_os_auth can read the user table', async () => {
    const auth = authClient();
    await auth.connect();
    try {
      const r = await auth.query('SELECT "id" FROM app."user"');
      expect(r.rows.length).toBeGreaterThan(0);
    } finally {
      await auth.end();
    }
  });

  it('clinic_os_auth CANNOT read patients or any tenant table', async () => {
    const auth = authClient();
    await auth.connect();
    try {
      await expect(auth.query('SELECT id FROM app.patients')).rejects.toThrow(/permission denied/i);
      await expect(auth.query('SELECT id FROM app.invoices')).rejects.toThrow(/permission denied/i);
    } finally {
      await auth.end();
    }
  });
});

describe('membership now references a real auth user', () => {
  it('clinic_users.user_id has a foreign key to app."user"', async () => {
    const res = await owner.query<{ n: string }>(
      `SELECT count(*)::text AS n
         FROM pg_constraint c
         JOIN pg_class src ON src.oid = c.conrelid
         JOIN pg_class tgt ON tgt.oid = c.confrelid
        WHERE c.contype = 'f' AND src.relname = 'clinic_users' AND tgt.relname = 'user'`,
    );
    expect(Number(res.rows[0]?.n)).toBe(1);
  });

  it('a membership row for a non-existent user is rejected', async () => {
    await expect(
      owner.query(
        `INSERT INTO app.clinic_users (user_id, organization_id, clinic_id, role)
         VALUES (gen_random_uuid(), $1, $2, 'doctor')`,
        [fx.orgA, fx.clinicA],
      ),
    ).rejects.toThrow(/violates foreign key constraint/i);
  });
});
