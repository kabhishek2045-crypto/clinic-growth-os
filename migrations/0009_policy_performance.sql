-- =============================================================================
-- 0009_policy_performance.sql
--
-- Makes the derived-membership policies from 0008 usable at scale.
--
-- 0008 moved membership from a trusted GUC to a live derivation, which is the
-- right security property and was measured to cost far too much:
--
--     50,000 patients, one tenant, SELECT count(*)
--       bare function calls in the policy   2,057 ms   InitPlan: no
--       IN (SELECT unnest(...))                24 ms   InitPlan: yes
--
-- The cause is visible in the plan. `organization_id = ANY (app.current_org_ids())`
-- is an array comparison, and the planner cannot hoist the function out of it, so
-- app.current_org_ids() and app.is_platform_admin() were each executed ONCE PER
-- ROW -- and after 0008 each of those executes a query. Two seconds for a single
-- count on a modest clinic.
--
-- Wrapping a call in a scalar subquery makes it an InitPlan: uncorrelated, so
-- Postgres evaluates it once per statement and reuses the result. `= ANY (array)`
-- cannot be written that way (`uuid = uuid[]` has no operator), so the array
-- membership becomes `IN (SELECT unnest(...))`, which can.
--
-- 117 of 130 policies are rewritten. Semantics are identical -- the predicates
-- were transformed mechanically from pg_policy rather than retyped -- and the
-- full isolation suite, including the forgery tests, is the check on that.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Future tables get the fast form too. Without this, the next CALL to one of
-- these procedures reintroduces a per-row policy and nothing complains.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE app.apply_tenant_rls(p_table text)
  LANGUAGE plpgsql
  SET search_path = pg_catalog, app
AS $$
BEGIN
  EXECUTE format('ALTER TABLE app.%I ENABLE ROW LEVEL SECURITY', p_table);
  EXECUTE format('ALTER TABLE app.%I FORCE  ROW LEVEL SECURITY', p_table);
  EXECUTE format(
    'CREATE POLICY %I ON app.%I FOR ALL TO clinic_os_app
       USING      ((SELECT app.is_platform_admin())
                   OR organization_id IN (SELECT unnest(app.current_org_ids())))
       WITH CHECK ((SELECT app.is_platform_admin())
                   OR organization_id IN (SELECT unnest(app.current_org_ids())))',
    p_table || '_tenant', p_table
  );
END;
$$;

CREATE OR REPLACE PROCEDURE app.apply_platform_rls(p_table text)
  LANGUAGE plpgsql
  SET search_path = pg_catalog, app
AS $$
BEGIN
  EXECUTE format('ALTER TABLE app.%I ENABLE ROW LEVEL SECURITY', p_table);
  EXECUTE format('ALTER TABLE app.%I FORCE  ROW LEVEL SECURITY', p_table);
  EXECUTE format(
    'CREATE POLICY %I ON app.%I FOR ALL TO clinic_os_app
       USING ((SELECT app.is_platform_admin())) WITH CHECK ((SELECT app.is_platform_admin()))',
    p_table || '_platform', p_table
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- Existing policies, transformed from pg_policy.
-- -----------------------------------------------------------------------------
DROP POLICY access_logs_insert ON app."access_logs";
CREATE POLICY access_logs_insert ON app."access_logs" FOR INSERT TO clinic_os_app
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY access_logs_select ON app."access_logs";
CREATE POLICY access_logs_select ON app."access_logs" FOR SELECT TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY allergies_tenant ON app."allergies";
CREATE POLICY allergies_tenant ON app."allergies" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY appointment_types_public_read ON app."appointment_types";
CREATE POLICY appointment_types_public_read ON app."appointment_types" FOR SELECT TO clinic_os_app
  USING ((organization_id = (SELECT app.current_public_org_id())));

DROP POLICY appointment_types_tenant ON app."appointment_types";
CREATE POLICY appointment_types_tenant ON app."appointment_types" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY appointments_patient_read ON app."appointments";
CREATE POLICY appointments_patient_read ON app."appointments" FOR SELECT TO clinic_os_app
  USING (((patient_id = (SELECT app.current_patient_id())) AND (organization_id = (SELECT app.current_patient_org_id()))));

DROP POLICY appointments_public_insert ON app."appointments";
CREATE POLICY appointments_public_insert ON app."appointments" FOR INSERT TO clinic_os_app
  WITH CHECK ((organization_id = (SELECT app.current_public_org_id())));

DROP POLICY appointments_tenant ON app."appointments";
CREATE POLICY appointments_tenant ON app."appointments" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY audit_logs_insert ON app."audit_logs";
CREATE POLICY audit_logs_insert ON app."audit_logs" FOR INSERT TO clinic_os_app
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY audit_logs_select ON app."audit_logs";
CREATE POLICY audit_logs_select ON app."audit_logs" FOR SELECT TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY automation_actions_tenant ON app."automation_actions";
CREATE POLICY automation_actions_tenant ON app."automation_actions" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY automation_rules_tenant ON app."automation_rules";
CREATE POLICY automation_rules_tenant ON app."automation_rules" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY automation_runs_tenant ON app."automation_runs";
CREATE POLICY automation_runs_tenant ON app."automation_runs" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY automation_templates_delete ON app."automation_templates";
CREATE POLICY automation_templates_delete ON app."automation_templates" FOR DELETE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()));

DROP POLICY automation_templates_insert ON app."automation_templates";
CREATE POLICY automation_templates_insert ON app."automation_templates" FOR INSERT TO clinic_os_app
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY automation_templates_update ON app."automation_templates";
CREATE POLICY automation_templates_update ON app."automation_templates" FOR UPDATE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()))
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY automation_triggers_tenant ON app."automation_triggers";
CREATE POLICY automation_triggers_tenant ON app."automation_triggers" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY campaign_recipients_tenant ON app."campaign_recipients";
CREATE POLICY campaign_recipients_tenant ON app."campaign_recipients" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY campaigns_tenant ON app."campaigns";
CREATE POLICY campaigns_tenant ON app."campaigns" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY clinic_branding_patient_read ON app."clinic_branding";
CREATE POLICY clinic_branding_patient_read ON app."clinic_branding" FOR SELECT TO clinic_os_app
  USING ((organization_id = (SELECT app.current_patient_org_id())));

DROP POLICY clinic_branding_public_read ON app."clinic_branding";
CREATE POLICY clinic_branding_public_read ON app."clinic_branding" FOR SELECT TO clinic_os_app
  USING ((organization_id = (SELECT app.current_public_org_id())));

DROP POLICY clinic_branding_tenant ON app."clinic_branding";
CREATE POLICY clinic_branding_tenant ON app."clinic_branding" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY clinic_domains_tenant ON app."clinic_domains";
CREATE POLICY clinic_domains_tenant ON app."clinic_domains" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY clinic_settings_tenant ON app."clinic_settings";
CREATE POLICY clinic_settings_tenant ON app."clinic_settings" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY clinic_users_tenant ON app."clinic_users";
CREATE POLICY clinic_users_tenant ON app."clinic_users" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY clinics_patient_read ON app."clinics";
CREATE POLICY clinics_patient_read ON app."clinics" FOR SELECT TO clinic_os_app
  USING ((organization_id = (SELECT app.current_patient_org_id())));

DROP POLICY clinics_public_read ON app."clinics";
CREATE POLICY clinics_public_read ON app."clinics" FOR SELECT TO clinic_os_app
  USING ((organization_id = (SELECT app.current_public_org_id())));

DROP POLICY clinics_tenant ON app."clinics";
CREATE POLICY clinics_tenant ON app."clinics" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY communication_preferences_tenant ON app."communication_preferences";
CREATE POLICY communication_preferences_tenant ON app."communication_preferences" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY communication_templates_tenant ON app."communication_templates";
CREATE POLICY communication_templates_tenant ON app."communication_templates" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY condition_timeline_events_tenant ON app."condition_timeline_events";
CREATE POLICY condition_timeline_events_tenant ON app."condition_timeline_events" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY consultation_notes_tenant ON app."consultation_notes";
CREATE POLICY consultation_notes_tenant ON app."consultation_notes" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY discounts_tenant ON app."discounts";
CREATE POLICY discounts_tenant ON app."discounts" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY doctor_availability_public_read ON app."doctor_availability";
CREATE POLICY doctor_availability_public_read ON app."doctor_availability" FOR SELECT TO clinic_os_app
  USING ((organization_id = (SELECT app.current_public_org_id())));

DROP POLICY doctor_availability_tenant ON app."doctor_availability";
CREATE POLICY doctor_availability_tenant ON app."doctor_availability" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY doctor_clinics_tenant ON app."doctor_clinics";
CREATE POLICY doctor_clinics_tenant ON app."doctor_clinics" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY doctors_patient_read ON app."doctors";
CREATE POLICY doctors_patient_read ON app."doctors" FOR SELECT TO clinic_os_app
  USING ((organization_id = (SELECT app.current_patient_org_id())));

DROP POLICY doctors_public_read ON app."doctors";
CREATE POLICY doctors_public_read ON app."doctors" FOR SELECT TO clinic_os_app
  USING ((organization_id = (SELECT app.current_public_org_id())));

DROP POLICY doctors_tenant ON app."doctors";
CREATE POLICY doctors_tenant ON app."doctors" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY domain_events_tenant ON app."domain_events";
CREATE POLICY domain_events_tenant ON app."domain_events" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY email_messages_tenant ON app."email_messages";
CREATE POLICY email_messages_tenant ON app."email_messages" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY entitlements_tenant ON app."entitlements";
CREATE POLICY entitlements_tenant ON app."entitlements" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY error_events_insert ON app."error_events";
CREATE POLICY error_events_insert ON app."error_events" FOR INSERT TO clinic_os_app
  WITH CHECK (((organization_id IS NULL) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY error_events_select ON app."error_events";
CREATE POLICY error_events_select ON app."error_events" FOR SELECT TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY family_recurrence_flags_tenant ON app."family_recurrence_flags";
CREATE POLICY family_recurrence_flags_tenant ON app."family_recurrence_flags" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY feature_flags_tenant ON app."feature_flags";
CREATE POLICY feature_flags_tenant ON app."feature_flags" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY features_delete ON app."features";
CREATE POLICY features_delete ON app."features" FOR DELETE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()));

DROP POLICY features_insert ON app."features";
CREATE POLICY features_insert ON app."features" FOR INSERT TO clinic_os_app
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY features_update ON app."features";
CREATE POLICY features_update ON app."features" FOR UPDATE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()))
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY followups_patient_read ON app."followups";
CREATE POLICY followups_patient_read ON app."followups" FOR SELECT TO clinic_os_app
  USING (((patient_id = (SELECT app.current_patient_id())) AND (organization_id = (SELECT app.current_patient_org_id()))));

DROP POLICY followups_tenant ON app."followups";
CREATE POLICY followups_tenant ON app."followups" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY health_conditions_patient_read ON app."health_conditions";
CREATE POLICY health_conditions_patient_read ON app."health_conditions" FOR SELECT TO clinic_os_app
  USING (((patient_id = (SELECT app.current_patient_id())) AND (organization_id = (SELECT app.current_patient_org_id()))));

DROP POLICY health_conditions_tenant ON app."health_conditions";
CREATE POLICY health_conditions_tenant ON app."health_conditions" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY households_tenant ON app."households";
CREATE POLICY households_tenant ON app."households" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY integration_connections_tenant ON app."integration_connections";
CREATE POLICY integration_connections_tenant ON app."integration_connections" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY invoice_items_tenant ON app."invoice_items";
CREATE POLICY invoice_items_tenant ON app."invoice_items" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY invoices_patient_read ON app."invoices";
CREATE POLICY invoices_patient_read ON app."invoices" FOR SELECT TO clinic_os_app
  USING (((patient_id = (SELECT app.current_patient_id())) AND (organization_id = (SELECT app.current_patient_org_id()))));

DROP POLICY invoices_tenant ON app."invoices";
CREATE POLICY invoices_tenant ON app."invoices" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY lead_events_tenant ON app."lead_events";
CREATE POLICY lead_events_tenant ON app."lead_events" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY lead_sources_tenant ON app."lead_sources";
CREATE POLICY lead_sources_tenant ON app."lead_sources" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY leads_public_insert ON app."leads";
CREATE POLICY leads_public_insert ON app."leads" FOR INSERT TO clinic_os_app
  WITH CHECK ((organization_id = (SELECT app.current_public_org_id())));

DROP POLICY leads_tenant ON app."leads";
CREATE POLICY leads_tenant ON app."leads" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY medical_history_tenant ON app."medical_history";
CREATE POLICY medical_history_tenant ON app."medical_history" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY opt_outs_tenant ON app."opt_outs";
CREATE POLICY opt_outs_tenant ON app."opt_outs" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY organizations_tenant ON app."organizations";
CREATE POLICY organizations_tenant ON app."organizations" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY patient_consents_tenant ON app."patient_consents";
CREATE POLICY patient_consents_tenant ON app."patient_consents" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY patient_documents_patient_read ON app."patient_documents";
CREATE POLICY patient_documents_patient_read ON app."patient_documents" FOR SELECT TO clinic_os_app
  USING (((patient_id = (SELECT app.current_patient_id())) AND (organization_id = (SELECT app.current_patient_org_id()))));

DROP POLICY patient_documents_tenant ON app."patient_documents";
CREATE POLICY patient_documents_tenant ON app."patient_documents" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY patient_household_links_tenant ON app."patient_household_links";
CREATE POLICY patient_household_links_tenant ON app."patient_household_links" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY patient_timeline_events_tenant ON app."patient_timeline_events";
CREATE POLICY patient_timeline_events_tenant ON app."patient_timeline_events" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY patients_patient_read ON app."patients";
CREATE POLICY patients_patient_read ON app."patients" FOR SELECT TO clinic_os_app
  USING ((id = (SELECT app.current_patient_id())));

DROP POLICY patients_public_insert ON app."patients";
CREATE POLICY patients_public_insert ON app."patients" FOR INSERT TO clinic_os_app
  WITH CHECK ((organization_id = (SELECT app.current_public_org_id())));

DROP POLICY patients_tenant ON app."patients";
CREATE POLICY patients_tenant ON app."patients" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY payment_transactions_tenant ON app."payment_transactions";
CREATE POLICY payment_transactions_tenant ON app."payment_transactions" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY payments_tenant ON app."payments";
CREATE POLICY payments_tenant ON app."payments" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY permissions_delete ON app."permissions";
CREATE POLICY permissions_delete ON app."permissions" FOR DELETE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()));

DROP POLICY permissions_insert ON app."permissions";
CREATE POLICY permissions_insert ON app."permissions" FOR INSERT TO clinic_os_app
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY permissions_update ON app."permissions";
CREATE POLICY permissions_update ON app."permissions" FOR UPDATE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()))
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY plan_features_delete ON app."plan_features";
CREATE POLICY plan_features_delete ON app."plan_features" FOR DELETE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()));

DROP POLICY plan_features_insert ON app."plan_features";
CREATE POLICY plan_features_insert ON app."plan_features" FOR INSERT TO clinic_os_app
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY plan_features_update ON app."plan_features";
CREATE POLICY plan_features_update ON app."plan_features" FOR UPDATE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()))
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY plans_delete ON app."plans";
CREATE POLICY plans_delete ON app."plans" FOR DELETE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()));

DROP POLICY plans_insert ON app."plans";
CREATE POLICY plans_insert ON app."plans" FOR INSERT TO clinic_os_app
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY plans_update ON app."plans";
CREATE POLICY plans_update ON app."plans" FOR UPDATE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()))
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY platform_admins_admin_only ON app."platform_admins";
CREATE POLICY platform_admins_admin_only ON app."platform_admins" FOR ALL TO clinic_os_app
  USING ((SELECT app.is_platform_admin()))
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY prescription_items_patient_read ON app."prescription_items";
CREATE POLICY prescription_items_patient_read ON app."prescription_items" FOR SELECT TO clinic_os_app
  USING ((((SELECT app.current_patient_id()) IS NOT NULL) AND app.patient_owns_prescription(prescription_id)));

DROP POLICY prescription_items_tenant ON app."prescription_items";
CREATE POLICY prescription_items_tenant ON app."prescription_items" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY prescriptions_patient_read ON app."prescriptions";
CREATE POLICY prescriptions_patient_read ON app."prescriptions" FOR SELECT TO clinic_os_app
  USING (((patient_id = (SELECT app.current_patient_id())) AND (organization_id = (SELECT app.current_patient_org_id()))));

DROP POLICY prescriptions_tenant ON app."prescriptions";
CREATE POLICY prescriptions_tenant ON app."prescriptions" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY referral_sources_tenant ON app."referral_sources";
CREATE POLICY referral_sources_tenant ON app."referral_sources" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY reviews_tenant ON app."reviews";
CREATE POLICY reviews_tenant ON app."reviews" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY role_permissions_delete ON app."role_permissions";
CREATE POLICY role_permissions_delete ON app."role_permissions" FOR DELETE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()));

DROP POLICY role_permissions_insert ON app."role_permissions";
CREATE POLICY role_permissions_insert ON app."role_permissions" FOR INSERT TO clinic_os_app
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY role_permissions_update ON app."role_permissions";
CREATE POLICY role_permissions_update ON app."role_permissions" FOR UPDATE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()))
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY roles_delete ON app."roles";
CREATE POLICY roles_delete ON app."roles" FOR DELETE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()));

DROP POLICY roles_insert ON app."roles";
CREATE POLICY roles_insert ON app."roles" FOR INSERT TO clinic_os_app
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY roles_update ON app."roles";
CREATE POLICY roles_update ON app."roles" FOR UPDATE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()))
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY services_public_read ON app."services";
CREATE POLICY services_public_read ON app."services" FOR SELECT TO clinic_os_app
  USING ((organization_id = (SELECT app.current_public_org_id())));

DROP POLICY services_tenant ON app."services";
CREATE POLICY services_tenant ON app."services" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY sms_messages_tenant ON app."sms_messages";
CREATE POLICY sms_messages_tenant ON app."sms_messages" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY staff_tenant ON app."staff";
CREATE POLICY staff_tenant ON app."staff" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY subscriptions_tenant ON app."subscriptions";
CREATE POLICY subscriptions_tenant ON app."subscriptions" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY system_events_select ON app."system_events";
CREATE POLICY system_events_select ON app."system_events" FOR SELECT TO clinic_os_app
  USING ((SELECT app.is_platform_admin()));

DROP POLICY taxes_tenant ON app."taxes";
CREATE POLICY taxes_tenant ON app."taxes" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY usage_counters_tenant ON app."usage_counters";
CREATE POLICY usage_counters_tenant ON app."usage_counters" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY usage_events_insert ON app."usage_events";
CREATE POLICY usage_events_insert ON app."usage_events" FOR INSERT TO clinic_os_app
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY usage_events_select ON app."usage_events";
CREATE POLICY usage_events_select ON app."usage_events" FOR SELECT TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY user_profiles_tenant ON app."user_profiles";
CREATE POLICY user_profiles_tenant ON app."user_profiles" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY webhooks_tenant ON app."webhooks";
CREATE POLICY webhooks_tenant ON app."webhooks" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY website_sections_public_read ON app."website_sections";
CREATE POLICY website_sections_public_read ON app."website_sections" FOR SELECT TO clinic_os_app
  USING ((organization_id = (SELECT app.current_public_org_id())));

DROP POLICY website_sections_tenant ON app."website_sections";
CREATE POLICY website_sections_tenant ON app."website_sections" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY website_templates_delete ON app."website_templates";
CREATE POLICY website_templates_delete ON app."website_templates" FOR DELETE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()));

DROP POLICY website_templates_insert ON app."website_templates";
CREATE POLICY website_templates_insert ON app."website_templates" FOR INSERT TO clinic_os_app
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY website_templates_update ON app."website_templates";
CREATE POLICY website_templates_update ON app."website_templates" FOR UPDATE TO clinic_os_app
  USING ((SELECT app.is_platform_admin()))
  WITH CHECK ((SELECT app.is_platform_admin()));

DROP POLICY websites_public_read ON app."websites";
CREATE POLICY websites_public_read ON app."websites" FOR SELECT TO clinic_os_app
  USING ((organization_id = (SELECT app.current_public_org_id())));

DROP POLICY websites_tenant ON app."websites";
CREATE POLICY websites_tenant ON app."websites" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

DROP POLICY whatsapp_messages_tenant ON app."whatsapp_messages";
CREATE POLICY whatsapp_messages_tenant ON app."whatsapp_messages" FOR ALL TO clinic_os_app
  USING (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))))
  WITH CHECK (((SELECT app.is_platform_admin()) OR (organization_id IN (SELECT unnest(app.current_org_ids())))));

