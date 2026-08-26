-- =============================================================================
-- 0008_derived_membership.sql
--
-- Policies stop trusting a pre-computed array and re-derive membership instead.
--
-- Until now set_tenant_context() computed the caller's organizations and wrote
-- them into app.current_org_ids, and every policy trusted that array. Postgres
-- has no ACL on custom GUCs, so anything able to execute arbitrary SQL as
-- clinic_os_app could simply:
--
--     SET LOCAL app.current_org_ids   = '<any organization uuid>';
--     SET LOCAL app.is_platform_admin = 'true';
--
-- and read every patient record on the platform. The tagged-template seam in
-- src/lib/db/sql.ts closed the application path to that, but it did not make the
-- claim unforgeable — it only made it hard to reach.
--
-- After this migration the GUCs are CLAIMS THAT GET CHECKED rather than facts
-- that get trusted. set_tenant_context writes exactly two values:
--
--     app.current_user_id     who the application says the caller is
--     app.request_elevation   whether they asked to act as a platform admin
--
-- and both are re-derived against the database on every policy evaluation.
-- Forging current_org_ids now does nothing at all: no policy reads it. Forging
-- is_platform_admin does nothing: it is computed, not read. The attacker's best
-- remaining move is to forge current_user_id to a REAL staff member of the
-- target organization — which needs a valid uuid they do not have, and which
-- yields exactly that person's real access rather than everything.
--
-- Recursion is the reason for the extra role. The derivation reads
-- app.clinic_users, which is itself FORCE RLS with a policy that would call the
-- derivation — an infinite loop. A SECURITY DEFINER function owned by a role
-- with BYPASSRLS breaks it. clinic_os_rls has BYPASSRLS, NOLOGIN, and no grants
-- to anyone: it exists solely to own these three functions. clinic_os_app is not
-- a member, so the "cannot reach a role with BYPASSRLS" test still holds.
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'clinic_os_rls') THEN
    CREATE ROLE clinic_os_rls NOLOGIN NOINHERIT BYPASSRLS;
  END IF;
END
$$;

-- CREATE as well as USAGE: Postgres requires a function's owner to hold CREATE
-- on the schema, so ownership cannot be reassigned without it.
GRANT USAGE, CREATE ON SCHEMA app TO clinic_os_rls;
GRANT SELECT ON app.clinic_users, app.platform_admins TO clinic_os_rls;

-- Required to reassign function ownership below: ALTER FUNCTION ... OWNER TO
-- demands membership in the target role. BYPASSRLS is a role ATTRIBUTE, and
-- attributes are not inherited through membership -- only assumed via SET ROLE
-- -- so the migration role does not silently acquire it, and clinic_os_app is
-- never granted membership at all.
GRANT clinic_os_rls TO CURRENT_USER;

-- -----------------------------------------------------------------------------
-- Derivation. STABLE so the planner may evaluate once per statement rather than
-- once per row; clinic_users(user_id) is indexed for the lookup.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.current_org_ids() RETURNS uuid[]
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = pg_catalog, app
AS $$
  SELECT COALESCE(array_agg(DISTINCT cu.organization_id), ARRAY[]::uuid[])
    FROM app.clinic_users cu
   WHERE cu.user_id = app.current_user_id()
     AND cu.deleted_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION app.current_clinic_ids() RETURNS uuid[]
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = pg_catalog, app
AS $$
  SELECT COALESCE(array_agg(DISTINCT cu.clinic_id), ARRAY[]::uuid[])
    FROM app.clinic_users cu
   WHERE cu.user_id = app.current_user_id()
     AND cu.deleted_at IS NULL;
$$;

-- Elevation is now a CONJUNCTION: the caller must have asked for it AND actually
-- hold an unexpired grant. Forging either half alone achieves nothing.
CREATE OR REPLACE FUNCTION app.is_platform_admin() RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = pg_catalog, app
AS $$
  SELECT COALESCE(current_setting('app.request_elevation', true), 'false') = 'true'
     AND EXISTS (
           SELECT 1 FROM app.platform_admins pa
            WHERE pa.user_id = app.current_user_id()
              AND (pa.expires_at IS NULL OR pa.expires_at > now())
         );
$$;

ALTER FUNCTION app.current_org_ids()    OWNER TO clinic_os_rls;
ALTER FUNCTION app.current_clinic_ids() OWNER TO clinic_os_rls;
ALTER FUNCTION app.is_platform_admin()  OWNER TO clinic_os_rls;

-- -----------------------------------------------------------------------------
-- set_tenant_context now writes only what cannot be derived: who the caller is,
-- and whether they asked to elevate. It no longer computes membership, so there
-- is nothing left for it to get wrong or for a caller to forge.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.set_tenant_context(p_user_id uuid, p_elevate boolean DEFAULT false)
  RETURNS void
  LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, app
AS $$
DECLARE
  v_may_elevate boolean;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'set_tenant_context: user id is required'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  PERFORM app.assert_no_principal();

  IF p_elevate THEN
    SELECT EXISTS (
      SELECT 1 FROM app.platform_admins pa
       WHERE pa.user_id = p_user_id
         AND (pa.expires_at IS NULL OR pa.expires_at > now())
    ) INTO v_may_elevate;

    IF NOT v_may_elevate THEN
      RAISE EXCEPTION 'set_tenant_context: user is not an active platform admin'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  PERFORM set_config('app.current_user_id',    p_user_id::text, true),
          set_config('app.request_elevation',  p_elevate::text, true);

  -- Deliberately NOT set: app.current_org_ids, app.current_clinic_ids,
  -- app.is_platform_admin. Every one of those is now derived. Writing them here
  -- would recreate exactly the forgeable surface this migration removes.
END;
$$;

REVOKE ALL ON FUNCTION app.set_tenant_context(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.set_tenant_context(uuid, boolean) TO clinic_os_app;

-- current_principal() reads current_user_id, which is unchanged, but the stale
-- GUCs must stop influencing it.
CREATE OR REPLACE FUNCTION app.clear_stale_context() RETURNS void
  LANGUAGE sql VOLATILE
  SET search_path = pg_catalog
AS $$
  SELECT set_config('app.current_org_ids', '', true),
         set_config('app.current_clinic_ids', '', true),
         set_config('app.is_platform_admin', '', true);
  SELECT NULL::void;
$$;
GRANT EXECUTE ON FUNCTION app.clear_stale_context() TO clinic_os_app;
