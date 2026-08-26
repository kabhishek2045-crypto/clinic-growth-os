-- =============================================================================
-- 0003_review_fixes.sql
--
-- Fixes three policy defects found by the /autoplan eng review. Each was
-- verified against the running schema before this migration was written.
--
--   C3  error_events could never be written to.
--   C5  audit_logs / access_logs were deletable by the tenant they audit.
--   C2  clear_tenant_context() was dead code that read like a control.
--
-- See docs/PHASE1_PLAN.md for the full findings.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- C3. error_events and system_events were unwritable
--
-- error_events.organization_id is nullable on purpose: a failed login, an
-- unknown-host lookup, or an exhausted connection pool has no tenant. But the
-- table was given the standard tenant policy, whose WITH CHECK is
--
--     organization_id = ANY (app.current_org_ids())
--
-- and `NULL = ANY (...)` evaluates to NULL, never TRUE. So an untenanted error
-- could never be inserted -- which is precisely the class of failure that most
-- needs logging. A tenanted one could only be written by a session that already
-- held that tenant's context, excluding most of the interesting cases.
--
-- system_events had the mirror problem: platform-only FOR ALL meant the
-- application could not write a system event at all.
-- -----------------------------------------------------------------------------
DROP POLICY error_events_tenant ON app.error_events;

CREATE POLICY error_events_insert ON app.error_events
  FOR INSERT TO clinic_os_app
  WITH CHECK (organization_id IS NULL OR organization_id = ANY (app.current_org_ids()));

CREATE POLICY error_events_select ON app.error_events
  FOR SELECT TO clinic_os_app
  USING (app.is_platform_admin() OR organization_id = ANY (app.current_org_ids()));

-- Deliberately no UPDATE or DELETE policy: an error record is append-only.
--
-- NOTE for callers: `INSERT ... RETURNING` requires the new row to pass the
-- SELECT policy as well as the INSERT one. An untenanted error row is not
-- readable by a session with no tenant context, so RETURNING will fail on it
-- even though the write succeeds. Log errors with a bare INSERT.

DROP POLICY system_events_platform ON app.system_events;

CREATE POLICY system_events_insert ON app.system_events
  FOR INSERT TO clinic_os_app
  WITH CHECK (true);

CREATE POLICY system_events_select ON app.system_events
  FOR SELECT TO clinic_os_app
  USING (app.is_platform_admin());

-- -----------------------------------------------------------------------------
-- C5. Append-only tables were writable in both directions
--
-- audit_logs, access_logs and usage_events were given FOR ALL, so any member of
-- an organization -- including read_only_staff -- could DELETE their own audit
-- trail or fabricate entries. An audit log the audited party can rewrite is not
-- an audit log, and under India's DPDP breach-notification posture that is a
-- compliance problem rather than a hygiene one.
--
-- Split into SELECT + INSERT. The absence of UPDATE and DELETE policies is the
-- control: with RLS forced and no permissive policy, both are denied.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['audit_logs', 'access_logs', 'usage_events'] LOOP
    EXECUTE format('DROP POLICY %I ON app.%I', t || '_tenant', t);

    EXECUTE format(
      'CREATE POLICY %I ON app.%I FOR SELECT TO clinic_os_app
         USING (app.is_platform_admin() OR organization_id = ANY (app.current_org_ids()))',
      t || '_select', t
    );

    EXECUTE format(
      'CREATE POLICY %I ON app.%I FOR INSERT TO clinic_os_app
         WITH CHECK (app.is_platform_admin() OR organization_id = ANY (app.current_org_ids()))',
      t || '_insert', t
    );
  END LOOP;
END
$$;

-- -----------------------------------------------------------------------------
-- C2. clear_tenant_context() was dead code
--
-- It was called from a finally block AFTER COMMIT. Outside a transaction,
-- set_config(..., is_local => true) reverts at the end of the statement, so the
-- call did nothing at all -- while its comment claimed it meant "a leak needs
-- two independent failures, not one". COMMIT and ROLLBACK already discard
-- SET LOCAL; that was always the whole mechanism.
--
-- It was also the only context function never REVOKEd from PUBLIC. Dropping it
-- removes a wasted round trip, a misleading comment, and a stray grant.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS app.clear_tenant_context();
