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
  patientA2: string;
  householdA: string;
  conditionA: string;
  conditionA2: string;
  doctorA: string;
  orgB: string;
  clinicB: string;
  userB: string;
  patientB: string;
  householdB: string;
  conditionB: string;
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

  // §60 — "at least one household with multiple linked patients and one tagged
  // health_condition per tenant, to exercise the Family Health Graph."
  const patientA2 = await one(
    `INSERT INTO app.patients (organization_id, clinic_id, full_name, phone)
     VALUES ($1, $2, 'Rohan Patel', '+919000000003') RETURNING id`,
    [orgA, clinicA],
  );
  const householdA = await one(
    `INSERT INTO app.households (organization_id, clinic_id, name, primary_contact_patient_id)
     VALUES ($1, $2, 'Patel family', $3) RETURNING id`,
    [orgA, clinicA, patientA],
  );
  await owner.query(
    `INSERT INTO app.patient_household_links (organization_id, patient_id, household_id, relationship)
     VALUES ($1, $2, $3, 'self'), ($1, $4, $3, 'child')`,
    [orgA, patientA, householdA, patientA2],
  );
  const conditionA = await one(
    `INSERT INTO app.health_conditions
       (organization_id, clinic_id, patient_id, condition_code, display_name, status)
     VALUES ($1, $2, $3, 'E11', 'Type 2 diabetes mellitus', 'chronic') RETURNING id`,
    [orgA, clinicA, patientA],
  );

  const householdB = await one(
    `INSERT INTO app.households (organization_id, clinic_id, name)
     VALUES ($1, $2, 'Rao family') RETURNING id`,
    [orgB, clinicB],
  );
  await owner.query(
    `INSERT INTO app.patient_household_links (organization_id, patient_id, household_id, relationship)
     VALUES ($1, $2, $3, 'self')`,
    [orgB, patientB, householdB],
  );
  const conditionB = await one(
    `INSERT INTO app.health_conditions
       (organization_id, clinic_id, patient_id, condition_code, display_name, status)
     VALUES ($1, $2, $3, 'J30', 'Allergic rhinitis', 'active') RETURNING id`,
    [orgB, clinicB, patientB],
  );

  const doctorA = await one(
    `INSERT INTO app.doctors (organization_id, full_name, specialty, registration_number)
     VALUES ($1, 'Dr Meera Shah', 'General Physician', 'NMC-000001') RETURNING id`,
    [orgA],
  );

  // A SECOND patient in the SAME organization, with their own clinical record.
  // Without this, "a patient sees one condition" is true whether the policy
  // scopes by patient or merely by organization -- a mutation dropping the
  // patient_id predicate passed the whole suite until this row existed.
  const conditionA2 = await one(
    `INSERT INTO app.health_conditions
       (organization_id, clinic_id, patient_id, condition_code, display_name, status)
     VALUES ($1, $2, $3, 'J06', 'Acute upper respiratory infection', 'resolved') RETURNING id`,
    [orgA, clinicA, patientA2],
  );

  return {
    orgA,
    clinicA,
    userA,
    patientA,
    patientA2,
    householdA,
    conditionA,
    conditionA2,
    doctorA,
    orgB,
    clinicB,
    userB,
    patientB,
    householdB,
    conditionB,
    adminUser,
    strangerUser,
  };
}

/**
 * Truncates tenant data, leaving the platform catalogue (roles, permissions,
 * plans, features, templates) intact -- that is seeded by migration 0002 and is
 * not tenant data.
 *
 * Discovered rather than listed: a hardcoded list silently stops covering tables
 * added later, and a fixture that quietly leaves rows behind makes an isolation
 * test pass for the wrong reason.
 */
const CATALOG_TABLES = [
  'permissions',
  'roles',
  'role_permissions',
  'plans',
  'features',
  'plan_features',
  'automation_templates',
  'website_templates',
  'schema_migrations',
];

export async function truncateAll(owner: Client): Promise<void> {
  const res = await owner.query<{ relname: string }>(
    `SELECT c.relname
       FROM pg_class c
       JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'app' AND c.relkind = 'r'`,
  );
  const targets = res.rows
    .map((r) => r.relname)
    .filter((t) => !CATALOG_TABLES.includes(t))
    .map((t) => `app.${t}`);
  if (targets.length > 0) {
    await owner.query(`TRUNCATE ${targets.join(', ')} CASCADE`);
  }
}
