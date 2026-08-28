-- =============================================================================
-- 0007_clinic_scope.sql
--
-- Closes the last unconstrained reference in the schema.
--
-- Twenty tables carried a `clinic_id` with NO foreign key to app.clinics at all,
-- so the column could hold any uuid — including another organization's clinic.
-- RLS did not catch it because every policy keys on organization_id and clinic is
-- an operational scope rather than a security boundary; a row stamped with the
-- right organization_id and a foreign clinic_id passed every check.
--
-- The consequence was not theoretical. Open decision 5 describes multi-location
-- UI as "a flag flip", and it could not have been: the moment clinic-scoped
-- queries went live, they would have returned other locations' rows and nothing
-- in the database would have objected.
--
-- ON DELETE RESTRICT rather than SET NULL, for two reasons. A composite SET NULL
-- would null organization_id too, which is NOT NULL. And §6 requires soft
-- deletion for records like these, so a clinic that has history should not be
-- hard-deletable in the first place — RESTRICT states that rather than silently
-- orphaning the rows.
--
-- These are additive: clinic_id stays nullable, and MATCH SIMPLE means a NULL in
-- either column satisfies the constraint, so org-level rows are unaffected.
-- =============================================================================

ALTER TABLE app.audit_logs
  ADD CONSTRAINT audit_logs_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.automation_rules
  ADD CONSTRAINT automation_rules_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.campaigns
  ADD CONSTRAINT campaigns_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.communication_templates
  ADD CONSTRAINT communication_templates_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.consultation_notes
  ADD CONSTRAINT consultation_notes_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.discounts
  ADD CONSTRAINT discounts_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.domain_events
  ADD CONSTRAINT domain_events_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.email_messages
  ADD CONSTRAINT email_messages_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.family_recurrence_flags
  ADD CONSTRAINT family_recurrence_flags_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.followups
  ADD CONSTRAINT followups_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.health_conditions
  ADD CONSTRAINT health_conditions_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.integration_connections
  ADD CONSTRAINT integration_connections_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.patient_consents
  ADD CONSTRAINT patient_consents_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.patient_documents
  ADD CONSTRAINT patient_documents_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.patient_timeline_events
  ADD CONSTRAINT patient_timeline_events_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.payments
  ADD CONSTRAINT payments_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.reviews
  ADD CONSTRAINT reviews_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.sms_messages
  ADD CONSTRAINT sms_messages_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.usage_events
  ADD CONSTRAINT usage_events_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.whatsapp_messages
  ADD CONSTRAINT whatsapp_messages_clinic_fk
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT;
