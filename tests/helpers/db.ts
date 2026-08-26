import { Client, Pool } from 'pg';

/**
 * The RLS suite runs against a REAL Postgres. There is no mock, and there must
 * never be one: §47 requires proof that cross-tenant access fails, and a mock can
 * only prove that our own test double refuses — which is worth nothing.
 *
 * Two connections, deliberately:
 *   owner — runs DDL and seeds fixtures, bypassing RLS
 *   app   — connects as clinic_os_app, which owns nothing; this is what the
 *           application uses and what every assertion below is made through
 */
export const ownerUrl = process.env.DATABASE_URL_UNPOOLED ?? process.env.MIGRATION_DATABASE_URL;
export const appUrl = process.env.DATABASE_URL;

export function requireUrls(): { ownerUrl: string; appUrl: string } {
  if (!ownerUrl || !appUrl) {
    throw new Error(
      'RLS tests need a real Postgres. Set DATABASE_URL (role clinic_os_app) and ' +
        'DATABASE_URL_UNPOOLED (owner role). See README "Running the RLS suite".',
    );
  }
  return { ownerUrl, appUrl };
}

export function ownerClient(): Client {
  return new Client({ connectionString: requireUrls().ownerUrl });
}

export function appPool(): Pool {
  return new Pool({ connectionString: requireUrls().appUrl, max: 4 });
}

export interface Fixture {
  orgA: string;
  clinicA: string;
  userA: string;
  patientA: string;
  orgB: string;
  clinicB: string;
  userB: string;
  patientB: string;
  adminUser: string;
  strangerUser: string;
}

/** Two tenants with no relationship whatsoever, per §60. */
export async function seed(owner: Client): Promise<Fixture> {
  const one = async (sql: string, values: unknown[] = []): Promise<string> => {
    const res = await owner.query<{ id: string }>(sql, values);
    const row = res.rows[0];
    if (!row) throw new Error(`seed statement returned no row: ${sql}`);
    return row.id;
  };

  const orgA = await one(
    `INSERT INTO app.organizations (name, slug) VALUES ('ABC Clinic', 'abc') RETURNING id`,
  );
  const orgB = await one(
    `INSERT INTO app.organizations (name, slug) VALUES ('XYZ Clinic', 'xyz') RETURNING id`,
  );

  const clinicA = await one(
    `INSERT INTO app.clinics (organization_id, name) VALUES ($1, 'ABC Main') RETURNING id`,
    [orgA],
  );
  const clinicB = await one(
    `INSERT INTO app.clinics (organization_id, name) VALUES ($1, 'XYZ Main') RETURNING id`,
    [orgB],
  );

  const userA = crypto.randomUUID();
  const userB = crypto.randomUUID();
  const adminUser = crypto.randomUUID();
  const strangerUser = crypto.randomUUID(); // authenticated, but member of nothing

  await owner.query(
    `INSERT INTO app.clinic_users (user_id, organization_id, clinic_id, role)
     VALUES ($1, $2, $3, 'clinic_owner'), ($4, $5, $6, 'clinic_owner')`,
    [userA, orgA, clinicA, userB, orgB, clinicB],
  );
  await owner.query(`INSERT INTO app.platform_admins (user_id) VALUES ($1)`, [adminUser]);

  const patientA = await one(
    `INSERT INTO app.patients (organization_id, clinic_id, full_name, phone)
     VALUES ($1, $2, 'Asha Patel', '+919000000001') RETURNING id`,
    [orgA, clinicA],
  );
  const patientB = await one(
    `INSERT INTO app.patients (organization_id, clinic_id, full_name, phone)
     VALUES ($1, $2, 'Bhavin Rao', '+919000000002') RETURNING id`,
    [orgB, clinicB],
  );

  return {
    orgA,
    clinicA,
    userA,
    patientA,
    orgB,
    clinicB,
    userB,
    patientB,
    adminUser,
    strangerUser,
  };
}

export async function truncateAll(owner: Client): Promise<void> {
  await owner.query(
    `TRUNCATE app.patients, app.clinic_users, app.platform_admins, app.clinics, app.organizations CASCADE`,
  );
}
