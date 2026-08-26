-- =============================================================================
-- 0005_explicit_elevation.sql
--
-- Platform-admin elevation was implicit, permanent and unaudited.
--
-- set_tenant_context() set app.is_platform_admin unconditionally for anyone in
-- platform_admins, so an admin who logged into the ordinary application crossed
-- every tenant boundary on every request -- no gesture, no time bound, no log.
-- withPlatformAdmin() in the TypeScript layer validated that a `reason` was
-- non-empty and then discarded it, so audit_logs.impersonation_reason -- a
-- column that exists specifically for this -- could never be populated.
--
-- The test suite asserted the old behaviour as CORRECT, under the heading
-- "platform administration is separate and explicit". It was neither.
--
-- After this migration: elevation is a deliberate act, it expires, and it is
-- recorded before any elevated statement runs.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Elevation can expire
--
-- §39 asks for "time-bounded access where possible" and M11 promises audited,
-- time-bounded impersonation. platform_admins had no expiry column to build on.
-- NULL means no expiry, which is right for a genuine platform owner; a support
-- engineer gets a date.
-- -----------------------------------------------------------------------------
ALTER TABLE app.platform_admins
  ADD COLUMN expires_at timestamptz,
  ADD COLUMN granted_by uuid,
  ADD COLUMN note       text;

-- -----------------------------------------------------------------------------
-- 2. Elevation must be asked for
--
-- The one-argument form is dropped rather than kept alongside, because a default
-- argument on a second overload would make every existing single-argument call
-- ambiguous. Callers that do not elevate are unchanged: set_tenant_context($1).
-- -----------------------------------------------------------------------------
DROP FUNCTION app.set_tenant_context(uuid);

CREATE FUNCTION app.set_tenant_context(p_user_id uuid, p_elevate boolean DEFAULT false)
  RETURNS void
  LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, app
AS $$
DECLARE
  v_org_ids    uuid[];
  v_clinic_ids uuid[];
  v_may_elevate boolean;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'set_tenant_context: user id is required'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  PERFORM app.assert_no_principal();

  SELECT COALESCE(array_agg(DISTINCT cu.organization_id), ARRAY[]::uuid[]),
         COALESCE(array_agg(DISTINCT cu.clinic_id),       ARRAY[]::uuid[])
    INTO v_org_ids, v_clinic_ids
    FROM app.clinic_users cu
   WHERE cu.user_id = p_user_id
     AND cu.deleted_at IS NULL;

  SELECT EXISTS (
    SELECT 1 FROM app.platform_admins pa
     WHERE pa.user_id = p_user_id
       AND (pa.expires_at IS NULL OR pa.expires_at > now())
  ) INTO v_may_elevate;

  -- Asking to elevate without the grant is an error, not a silent downgrade.
  -- A caller that believes it is elevated and is not would otherwise read zero
  -- rows and conclude the data is missing.
  IF p_elevate AND NOT v_may_elevate THEN
    RAISE EXCEPTION 'set_tenant_context: user is not an active platform admin'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM set_config('app.current_user_id',    p_user_id::text,                    true),
          set_config('app.current_org_ids',    array_to_string(v_org_ids, ','),    true),
          set_config('app.current_clinic_ids', array_to_string(v_clinic_ids, ','), true),
          -- The whole change is on this line: elevation only when it was asked for.
          set_config('app.is_platform_admin',  (p_elevate AND v_may_elevate)::text, true);
END;
$$;

REVOKE ALL ON FUNCTION app.set_tenant_context(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.set_tenant_context(uuid, boolean) TO clinic_os_app;

-- -----------------------------------------------------------------------------
-- 3. Elevation is recorded before it is used
--
-- Written to system_events, not audit_logs: audit_logs.organization_id is NOT
-- NULL, and an elevation is a platform-level act that may span tenants or none.
-- audit_logs.impersonation_reason remains for the per-action records the
-- application writes once inside a specific tenant (M11).
--
-- Runs inside the caller's transaction, so an elevation that rolls back leaves
-- no record of access that never happened -- and an elevation that commits
-- cannot have acted before the record existed.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.begin_elevation(p_reason text)
  RETURNS uuid
  LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, app
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'begin_elevation: session is not elevated'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'begin_elevation: a reason is required'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  INSERT INTO app.system_events (event_type, payload)
  VALUES (
    'platform_admin.elevated',
    jsonb_build_object(
      'admin_user_id', app.current_user_id(),
      'reason',        btrim(p_reason)
    )
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION app.begin_elevation(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.begin_elevation(text) TO clinic_os_app;
