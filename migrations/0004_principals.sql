-- =============================================================================
-- 0004_principals.sql
--
-- Adds the missing principals to the isolation model.
--
-- Until now app.set_tenant_context() derived access solely from app.clinic_users,
-- so the only principal that could reach any row was an authenticated clinic
-- staff member. Everything else got an empty array: zero rows on read, rejection
-- on write. That blocks:
--
--   M3   resolveTenantFromHost() must read clinic_domains BEFORE authentication
--   M8   the Razorpay webhook is an unauthenticated POST that must write
--   M9   public booking must read services/doctors and write leads/appointments
--   M10a the cron outbox worker has no user id at all
--   M12  patients appear in no clinic_users row, so they see nothing
--
-- Three principals now exist, and they are MUTUALLY EXCLUSIVE within a
-- transaction. Each keys on its own GUC:
--
--   staff    app.current_org_ids       (set only by set_tenant_context)
--   public   app.current_public_org_id (set only by set_public_context)
--   patient  app.current_patient_id    (set only by set_patient_context)
--
-- The separation is the security property. If set_public_context populated
-- app.current_org_ids, every existing _tenant policy would fire for an anonymous
-- visitor and hand them the whole tenant. It must never do that, and the
-- exclusivity guard below makes mixing them an error rather than a subtlety.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Context readers for the new principals. Fail closed, like the originals.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.current_public_org_id() RETURNS uuid
  LANGUAGE sql STABLE PARALLEL SAFE
  SET search_path = pg_catalog
AS $$
  SELECT NULLIF(current_setting('app.current_public_org_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION app.current_patient_id() RETURNS uuid
  LANGUAGE sql STABLE PARALLEL SAFE
  SET search_path = pg_catalog
AS $$
  SELECT NULLIF(current_setting('app.current_patient_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION app.current_patient_org_id() RETURNS uuid
  LANGUAGE sql STABLE PARALLEL SAFE
  SET search_path = pg_catalog
AS $$
  SELECT NULLIF(current_setting('app.current_patient_org_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION app.current_principal() RETURNS text
  LANGUAGE sql STABLE PARALLEL SAFE
  SET search_path = pg_catalog, app
AS $$
  SELECT CASE
           WHEN app.current_user_id()        IS NOT NULL THEN 'staff'
           WHEN app.current_patient_id()     IS NOT NULL THEN 'patient'
           WHEN app.current_public_org_id()  IS NOT NULL THEN 'public'
           ELSE 'none'
         END;
$$;

-- -----------------------------------------------------------------------------
-- 2. Exclusivity guard
--
-- Two principals in one transaction is always a bug, and a dangerous one: it
-- would let a public request inherit staff reach. Raise rather than merge.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.assert_no_principal() RETURNS void
  LANGUAGE plpgsql VOLATILE
  SET search_path = pg_catalog, app
AS $$
DECLARE
  v_current text;
BEGIN
  v_current := app.current_principal();
  IF v_current <> 'none' THEN
    RAISE EXCEPTION 'a % principal is already set in this transaction', v_current
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
END;
$$;

-- Retrofit the guard onto the staff setter too.
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
  PERFORM app.assert_no_principal();

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

-- -----------------------------------------------------------------------------
-- 3. Public principal
--
-- For host-resolved anonymous traffic: the clinic's own website, the public
-- booking flow, unauthenticated webhooks. Grants NOTHING by itself -- only the
-- explicit public policies in section 6 respond to it.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.set_public_context(p_org_id uuid)
  RETURNS void
  LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, app
AS $$
BEGIN
  IF p_org_id IS NULL THEN
    RAISE EXCEPTION 'set_public_context: organization id is required'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  PERFORM app.assert_no_principal();

  -- The caller must have obtained p_org_id from app.resolve_domain(), which is
  -- the only sanctioned path from a hostname to an organization.
  IF NOT EXISTS (
    SELECT 1 FROM app.organizations o
     WHERE o.id = p_org_id AND o.deleted_at IS NULL AND o.status <> 'suspended'
  ) THEN
    RAISE EXCEPTION 'set_public_context: unknown or suspended organization'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  PERFORM set_config('app.current_public_org_id', p_org_id::text, true);
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. Patient principal
--
-- Derives the organization from the patient row itself, so a caller cannot
-- assert a patient into an organization they do not belong to.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.set_patient_context(p_patient_id uuid)
  RETURNS void
  LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, app
AS $$
DECLARE
  v_org_id uuid;
BEGIN
  IF p_patient_id IS NULL THEN
    RAISE EXCEPTION 'set_patient_context: patient id is required'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  PERFORM app.assert_no_principal();

  SELECT p.organization_id INTO v_org_id
    FROM app.patients p
   WHERE p.id = p_patient_id AND p.deleted_at IS NULL;

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'set_patient_context: unknown patient'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  PERFORM set_config('app.current_patient_id',     p_patient_id::text, true),
          set_config('app.current_patient_org_id', v_org_id::text,     true);
END;
$$;

-- -----------------------------------------------------------------------------
-- 5. Domain resolution
--
-- The chicken-and-egg case: resolving a hostname to a tenant has to happen
-- BEFORE any principal exists. A narrow SECURITY DEFINER function is the answer
-- -- it returns only what routing needs, only for domains that are actually
-- live, and never exposes a general read of clinic_domains.
--
-- It also closes the enumeration oracle: clinic_domains.normalized_domain is a
-- GLOBAL unique index, and unique-index validation bypasses RLS, so a tenant
-- could previously discover which custom domains exist platform-wide by
-- observing 23505 versus success. Callers use this function and get a row or
-- nothing; they never see the difference between "taken by someone else" and
-- "does not exist".
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.resolve_domain(p_host text)
  RETURNS TABLE (organization_id uuid, clinic_id uuid, status text)
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = pg_catalog, app
AS $$
  SELECT d.organization_id, d.clinic_id, d.status
    FROM app.clinic_domains d
    JOIN app.organizations o ON o.id = d.organization_id
   WHERE d.normalized_domain = lower(btrim(p_host))
     AND d.status IN ('verified', 'active')
     AND o.deleted_at IS NULL
     AND o.status <> 'suspended'
   LIMIT 1;
$$;

REVOKE ALL ON FUNCTION app.set_public_context(uuid)  FROM PUBLIC;
REVOKE ALL ON FUNCTION app.set_patient_context(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION app.resolve_domain(text)      FROM PUBLIC;
REVOKE ALL ON FUNCTION app.assert_no_principal()     FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.set_public_context(uuid)  TO clinic_os_app;
GRANT EXECUTE ON FUNCTION app.set_patient_context(uuid) TO clinic_os_app;
GRANT EXECUTE ON FUNCTION app.resolve_domain(text)      TO clinic_os_app;

-- =============================================================================
-- 6. Public policies
--
-- Additive. Postgres ORs permissive policies together, so these sit alongside
-- the existing _tenant policies without weakening them: a public session has an
-- empty app.current_org_ids, so no _tenant policy fires for it, and a staff
-- session has no app.current_public_org_id, so none of these fire for staff.
--
-- The read set is deliberately small -- exactly what §16's public pages need to
-- render (/, /about, /doctors, /services, /contact, /book-appointment) and
-- nothing else. Patients, appointments, invoices, prescriptions and every
-- clinical table are absent by design.
-- =============================================================================
DO $$
DECLARE
  t text;
  -- Tables a visitor may READ, scoped to the resolved organization.
  public_read text[] := ARRAY[
    'clinics', 'clinic_branding', 'doctors', 'services',
    'appointment_types', 'doctor_availability', 'websites', 'website_sections'
  ];
BEGIN
  FOREACH t IN ARRAY public_read LOOP
    EXECUTE format(
      'CREATE POLICY %I ON app.%I FOR SELECT TO clinic_os_app
         USING (organization_id = app.current_public_org_id())',
      t || '_public_read', t
    );
  END LOOP;
END
$$;

-- Public WRITE set. Insert-only, and every row must be stamped with the
-- resolved organization -- a visitor cannot write into a tenant they did not
-- arrive at. No SELECT: a visitor may create a lead or a booking and may not
-- read anyone's, including their own. The confirmation screen is rendered from
-- what the request already knows.
CREATE POLICY leads_public_insert ON app.leads
  FOR INSERT TO clinic_os_app
  WITH CHECK (organization_id = app.current_public_org_id());

CREATE POLICY patients_public_insert ON app.patients
  FOR INSERT TO clinic_os_app
  WITH CHECK (organization_id = app.current_public_org_id());

CREATE POLICY appointments_public_insert ON app.appointments
  FOR INSERT TO clinic_os_app
  WITH CHECK (organization_id = app.current_public_org_id());

-- =============================================================================
-- 7. Patient policies
--
-- A patient reaches their own records and the clinic's public face. Household
-- membership grants NOTHING here: §6 is explicit that a household is a grouping
-- construct and never a security boundary, so a parent does not see a spouse's
-- record by virtue of sharing one. Family access on the portal is a separate,
-- consent-gated feature and is not implied by this migration.
-- =============================================================================
CREATE POLICY patients_patient_read ON app.patients
  FOR SELECT TO clinic_os_app
  USING (id = app.current_patient_id());

DO $$
DECLARE
  t text;
  -- Tables carrying patient_id directly.
  patient_owned text[] := ARRAY[
    'appointments', 'prescriptions', 'invoices',
    'patient_documents', 'followups', 'health_conditions'
  ];
BEGIN
  FOREACH t IN ARRAY patient_owned LOOP
    EXECUTE format(
      'CREATE POLICY %I ON app.%I FOR SELECT TO clinic_os_app
         USING (patient_id = app.current_patient_id()
                AND organization_id = app.current_patient_org_id())',
      t || '_patient_read', t
    );
  END LOOP;
END
$$;

-- The clinic's own public face, readable by its patients.
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['clinics', 'clinic_branding', 'doctors'] LOOP
    EXECUTE format(
      'CREATE POLICY %I ON app.%I FOR SELECT TO clinic_os_app
         USING (organization_id = app.current_patient_org_id())',
      t || '_patient_read', t
    );
  END LOOP;
END
$$;

-- prescription_items has no patient_id of its own. A SECURITY DEFINER helper
-- resolves ownership without an RLS-visible subquery on the parent, which would
-- otherwise recurse through prescriptions' own policies.
CREATE OR REPLACE FUNCTION app.patient_owns_prescription(p_prescription_id uuid)
  RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = pg_catalog, app
AS $$
  SELECT EXISTS (
    SELECT 1 FROM app.prescriptions pr
     WHERE pr.id = p_prescription_id
       AND pr.patient_id = app.current_patient_id()
       AND pr.deleted_at IS NULL
  );
$$;
REVOKE ALL ON FUNCTION app.patient_owns_prescription(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.patient_owns_prescription(uuid) TO clinic_os_app;

CREATE POLICY prescription_items_patient_read ON app.prescription_items
  FOR SELECT TO clinic_os_app
  USING (app.current_patient_id() IS NOT NULL
         AND app.patient_owns_prescription(prescription_id));
