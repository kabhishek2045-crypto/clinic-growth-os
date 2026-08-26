-- =============================================================================
-- 0001_tenancy_spike.sql
-- MASTER_PROMPT §9, §9.1, §63 "First implementation milestone"
--
-- The tenant-isolation boundary. Every table added in later migrations inherits
-- this pattern, so it is proven here, on a deliberately small schema, before
-- anything is built on top of it.
--
-- Run as the OWNER role. The application NEVER connects as the owner.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS app;

-- -----------------------------------------------------------------------------
-- 1. Runtime role
--
-- Postgres lets a table's OWNER bypass that table's RLS policies. Neon's default
-- role owns everything it creates, so an app connecting as the owner would sail
-- straight through every policy below while all the tests still passed.
--
-- Two independent defences:
--   (a) the app connects as clinic_os_app, which owns nothing and has no BYPASSRLS
--   (b) every tenant table is set FORCE ROW LEVEL SECURITY (section 5 below)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'clinic_os_app') THEN
    CREATE ROLE clinic_os_app NOLOGIN NOINHERIT;
  END IF;
END
$$;

REVOKE ALL ON SCHEMA app FROM PUBLIC;
GRANT USAGE ON SCHEMA app TO clinic_os_app;

-- -----------------------------------------------------------------------------
-- 2. Tables (spike subset — organizations, clinics, membership, patients)
--
-- organization_id is the SECURITY boundary; clinic_id is an OPERATIONAL scope.
-- Both are denormalised onto every tenant-owned row so policies never join.
-- -----------------------------------------------------------------------------
CREATE TABLE app.organizations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  slug        text NOT NULL UNIQUE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz
);

CREATE TABLE app.clinics (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  name            text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  -- lets child tables carry (organization_id, clinic_id) and have the database
  -- guarantee the pair is consistent, so denormalisation cannot drift
  UNIQUE (organization_id, id)
);
CREATE INDEX clinics_org_idx ON app.clinics (organization_id);

-- Membership. The source of truth for what a user may reach; read by
-- app.set_tenant_context() below, never asserted by application code.
CREATE TABLE app.clinic_users (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL,
  organization_id uuid NOT NULL,
  clinic_id       uuid NOT NULL,
  role            text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  FOREIGN KEY (organization_id, clinic_id)
    REFERENCES app.clinics (organization_id, id) ON DELETE CASCADE,
  UNIQUE (user_id, clinic_id)
);
CREATE INDEX clinic_users_user_idx ON app.clinic_users (user_id) WHERE deleted_at IS NULL;

CREATE TABLE app.platform_admins (
  user_id    uuid PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.patients (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  clinic_id       uuid NOT NULL,
  full_name       text NOT NULL,
  phone           text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  FOREIGN KEY (organization_id, clinic_id)
    REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT
);
CREATE INDEX patients_org_idx   ON app.patients (organization_id) WHERE deleted_at IS NULL;
CREATE INDEX patients_phone_idx ON app.patients (organization_id, phone) WHERE deleted_at IS NULL;

-- -----------------------------------------------------------------------------
-- 3. Context readers
--
-- These read session settings only. They are deliberately NOT security definer:
-- least privilege, and there is nothing here to elevate for. Membership-derived
-- helpers (section 4) are the ones that need it.
--
-- Every one of them FAILS CLOSED. Absent or empty setting yields an empty array
-- or false, never "allow all" — the difference between an unconfigured request
-- seeing nothing and seeing everything.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.current_user_id() RETURNS uuid
  LANGUAGE sql STABLE PARALLEL SAFE
  SET search_path = pg_catalog
AS $$
  SELECT NULLIF(current_setting('app.current_user_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION app.current_org_ids() RETURNS uuid[]
  LANGUAGE sql STABLE PARALLEL SAFE
  SET search_path = pg_catalog
AS $$
  SELECT CASE
           WHEN COALESCE(current_setting('app.current_org_ids', true), '') = ''
             THEN ARRAY[]::uuid[]
           ELSE string_to_array(current_setting('app.current_org_ids', true), ',')::uuid[]
         END;
$$;

CREATE OR REPLACE FUNCTION app.current_clinic_ids() RETURNS uuid[]
  LANGUAGE sql STABLE PARALLEL SAFE
  SET search_path = pg_catalog
AS $$
  SELECT CASE
           WHEN COALESCE(current_setting('app.current_clinic_ids', true), '') = ''
             THEN ARRAY[]::uuid[]
           ELSE string_to_array(current_setting('app.current_clinic_ids', true), ',')::uuid[]
         END;
$$;

CREATE OR REPLACE FUNCTION app.is_platform_admin() RETURNS boolean
  LANGUAGE sql STABLE PARALLEL SAFE
  SET search_path = pg_catalog
AS $$
  SELECT COALESCE(current_setting('app.is_platform_admin', true), 'false') = 'true';
$$;

-- -----------------------------------------------------------------------------
-- 4. The JWT -> Postgres session bridge (§9.1)
--
-- The application passes ONE value: the user id it verified server-side from the
-- Better Auth session. The database derives which organizations and clinics that
-- user may reach, by reading app.clinic_users itself.
--
-- This is the point of the design. Application code never computes membership,
-- so an application bug cannot widen access — the widest a caller can get is
-- whatever clinic_users actually says.
--
-- Honest limit: Postgres has no ACL on custom GUCs, so a role that can execute
-- arbitrary SQL can still SET app.current_org_ids directly. This function removes
-- the far likelier failure (an app-code mistake), not full SQL-execution
-- compromise. Defence against that remains: parameterised queries everywhere,
-- and no raw string interpolation into SQL.
--
-- SET LOCAL, never SET: LOCAL is scoped to the transaction, so it cannot leak to
-- the next tenant on a backend recycled by Neon's transaction-mode pooler.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.set_tenant_context(p_user_id uuid)
  RETURNS void
  LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, app
AS $$
DECLARE
  v_org_ids    uuid[];
  v_clinic_ids uuid[];
  v_is_admin   boolean;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'set_tenant_context: user id is required'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT cu.organization_id), ARRAY[]::uuid[]),
         COALESCE(array_agg(DISTINCT cu.clinic_id),       ARRAY[]::uuid[])
    INTO v_org_ids, v_clinic_ids
    FROM app.clinic_users cu
   WHERE cu.user_id = p_user_id
     AND cu.deleted_at IS NULL;

  SELECT EXISTS (SELECT 1 FROM app.platform_admins pa WHERE pa.user_id = p_user_id)
    INTO v_is_admin;

  PERFORM set_config('app.current_user_id',    p_user_id::text,                    true),
          set_config('app.current_org_ids',    array_to_string(v_org_ids, ','),    true),
          set_config('app.current_clinic_ids', array_to_string(v_clinic_ids, ','), true),
          set_config('app.is_platform_admin',  v_is_admin::text,                   true);
END;
$$;

REVOKE ALL ON FUNCTION app.set_tenant_context(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.set_tenant_context(uuid) TO clinic_os_app;

-- Explicit teardown, so a pooled connection can be scrubbed in tests and in the
-- release path without relying on transaction rollback alone.
CREATE OR REPLACE FUNCTION app.clear_tenant_context() RETURNS void
  LANGUAGE sql VOLATILE
  SET search_path = pg_catalog
AS $$
  SELECT set_config('app.current_user_id',    '',      true),
         set_config('app.current_org_ids',    '',      true),
         set_config('app.current_clinic_ids', '',      true),
         set_config('app.is_platform_admin',  'false', true);
  SELECT NULL::void;
$$;
GRANT EXECUTE ON FUNCTION app.clear_tenant_context() TO clinic_os_app;

-- -----------------------------------------------------------------------------
-- 5. Row Level Security
--
-- ENABLE turns policies on for non-owners. FORCE also applies them to the owner.
-- Both, on every tenant-owned table, always.
--
-- WITH CHECK is written explicitly even though a FOR ALL policy that omits it
-- reuses its USING expression. Two reasons it still earns its place: it states
-- the write rule as intent rather than as an inherited default, and it survives
-- the day these are split into per-command policies -- at which point a FOR
-- INSERT policy has no USING to fall back on, and forgetting WITH CHECK there
-- would leave writes unconstrained. Verified by mutation test, not assumed.
-- -----------------------------------------------------------------------------
ALTER TABLE app.organizations  ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.organizations  FORCE  ROW LEVEL SECURITY;
ALTER TABLE app.clinics        ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.clinics        FORCE  ROW LEVEL SECURITY;
ALTER TABLE app.clinic_users   ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.clinic_users   FORCE  ROW LEVEL SECURITY;
ALTER TABLE app.patients       ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.patients       FORCE  ROW LEVEL SECURITY;
ALTER TABLE app.platform_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.platform_admins FORCE  ROW LEVEL SECURITY;

CREATE POLICY organizations_tenant ON app.organizations
  FOR ALL TO clinic_os_app
  USING      (app.is_platform_admin() OR id = ANY (app.current_org_ids()))
  WITH CHECK (app.is_platform_admin() OR id = ANY (app.current_org_ids()));

CREATE POLICY clinics_tenant ON app.clinics
  FOR ALL TO clinic_os_app
  USING      (app.is_platform_admin() OR organization_id = ANY (app.current_org_ids()))
  WITH CHECK (app.is_platform_admin() OR organization_id = ANY (app.current_org_ids()));

CREATE POLICY clinic_users_tenant ON app.clinic_users
  FOR ALL TO clinic_os_app
  USING      (app.is_platform_admin() OR organization_id = ANY (app.current_org_ids()))
  WITH CHECK (app.is_platform_admin() OR organization_id = ANY (app.current_org_ids()));

CREATE POLICY patients_tenant ON app.patients
  FOR ALL TO clinic_os_app
  USING      (app.is_platform_admin() OR organization_id = ANY (app.current_org_ids()))
  WITH CHECK (app.is_platform_admin() OR organization_id = ANY (app.current_org_ids()));

-- platform_admins is readable only by a platform admin; a clinic user can never
-- enumerate or grant platform administration.
CREATE POLICY platform_admins_admin_only ON app.platform_admins
  FOR ALL TO clinic_os_app
  USING      (app.is_platform_admin())
  WITH CHECK (app.is_platform_admin());

-- -----------------------------------------------------------------------------
-- 6. Grants. DML only — no DDL, no ownership, no BYPASSRLS.
-- -----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO clinic_os_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO clinic_os_app;
