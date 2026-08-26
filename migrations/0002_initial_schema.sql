-- =============================================================================
-- 0002_initial_schema.sql
-- MASTER_PROMPT §6, §7.2, §49 — the Phase 1 entity model.
--
-- Extends the four tables from the 0001 spike to full shape and adds the rest.
-- The Family Health Graph (§7.2) is here, not deferred: it is the single most
-- important "do it now" instruction in the specification, because condition
-- tags have to be written as events happen and cannot be inferred later.
--
-- The Visual Health Advisor tables (§32) are deliberately NOT here. §49 excludes
-- them by name, and they hang off health_conditions.condition_code, which IS
-- built here — so adding them in Phase 2 is additive, with no backfill.
--
-- Run as the OWNER role. The application never connects as the owner.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Primary keys
--
-- §6 requires UUID primary keys. Plain v4 is random, which scatters inserts
-- across the whole B-tree and fragments every index on a table that grows.
-- v7 is time-ordered, so inserts append. Postgres 18 ships uuidv7(); Neon is on
-- 17, so it is implemented here and version-checked in the test suite rather
-- than assumed.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.uuid_v7() RETURNS uuid
  LANGUAGE sql VOLATILE PARALLEL SAFE
  SET search_path = pg_catalog
AS $$
  SELECT encode(
    set_bit(
      set_bit(
        overlay(
          uuid_send(gen_random_uuid())
          PLACING substring(
            int8send(floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint)
            FROM 3
          )
          FROM 1 FOR 6
        ),
        52, 1
      ),
      53, 1
    ),
    'hex'
  )::uuid;
$$;

-- -----------------------------------------------------------------------------
-- 2. updated_at, maintained by the database
--
-- An application that forgets to set updated_at produces silently wrong audit
-- data. A trigger cannot forget.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.touch_updated_at() RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = pg_catalog
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- -----------------------------------------------------------------------------
-- 3. Uniform policy application
--
-- Sixty-five hand-written policies would be sixty-five chances to write a
-- subtly weaker one. There are exactly three access shapes in this schema, and
-- each is defined once here and applied by name.
--
--   tenant    - rows belong to an organization. The default for anything
--               clinical, commercial, or operational.
--   catalog   - platform-owned reference data (plans, features, templates).
--               Readable by any authenticated app session, writable only by a
--               platform administrator.
--   platform  - platform-only. Clinic users cannot read it at all.
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
       USING      (app.is_platform_admin() OR organization_id = ANY (app.current_org_ids()))
       WITH CHECK (app.is_platform_admin() OR organization_id = ANY (app.current_org_ids()))',
    p_table || '_tenant', p_table
  );
END;
$$;

CREATE OR REPLACE PROCEDURE app.apply_catalog_rls(p_table text)
  LANGUAGE plpgsql
  SET search_path = pg_catalog, app
AS $$
BEGIN
  EXECUTE format('ALTER TABLE app.%I ENABLE ROW LEVEL SECURITY', p_table);
  EXECUTE format('ALTER TABLE app.%I FORCE  ROW LEVEL SECURITY', p_table);
  -- Read is open to any app session; a catalog carries no tenant data.
  EXECUTE format(
    'CREATE POLICY %I ON app.%I FOR SELECT TO clinic_os_app USING (true)',
    p_table || '_read', p_table
  );
  -- Writes are platform-only, and split out so the read policy cannot
  -- accidentally grant them.
  EXECUTE format(
    'CREATE POLICY %I ON app.%I FOR INSERT TO clinic_os_app WITH CHECK (app.is_platform_admin())',
    p_table || '_insert', p_table
  );
  EXECUTE format(
    'CREATE POLICY %I ON app.%I FOR UPDATE TO clinic_os_app
       USING (app.is_platform_admin()) WITH CHECK (app.is_platform_admin())',
    p_table || '_update', p_table
  );
  EXECUTE format(
    'CREATE POLICY %I ON app.%I FOR DELETE TO clinic_os_app USING (app.is_platform_admin())',
    p_table || '_delete', p_table
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
       USING (app.is_platform_admin()) WITH CHECK (app.is_platform_admin())',
    p_table || '_platform', p_table
  );
END;
$$;

-- =============================================================================
-- 4. Tenancy and SaaS
-- =============================================================================

-- Extend the spike tables to full Phase 1 shape ------------------------------
ALTER TABLE app.organizations
  ADD COLUMN legal_name      text,
  ADD COLUMN status          text NOT NULL DEFAULT 'active'
    CHECK (status IN ('trial', 'active', 'grace_period', 'read_only', 'suspended', 'cancelled')),
  ADD COLUMN primary_contact_email text,
  ADD COLUMN primary_contact_phone text;

ALTER TABLE app.clinics
  ADD COLUMN slug           text,
  ADD COLUMN address_line1  text,
  ADD COLUMN address_line2  text,
  ADD COLUMN city           text,
  ADD COLUMN state          text,
  ADD COLUMN postal_code    text,
  ADD COLUMN country        text NOT NULL DEFAULT 'IN',
  ADD COLUMN timezone       text NOT NULL DEFAULT 'Asia/Kolkata',
  ADD COLUMN phone          text,
  ADD COLUMN email          text,
  ADD COLUMN is_primary     boolean NOT NULL DEFAULT false,
  ADD CONSTRAINT clinics_org_slug_unique UNIQUE (organization_id, slug);

-- §13 — permission-based authorization. The role column stays for display and
-- defaults; every actual check resolves through role_permissions.
ALTER TABLE app.clinic_users
  ADD COLUMN updated_at   timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN invited_at   timestamptz,
  ADD COLUMN accepted_at  timestamptz,
  ADD COLUMN status       text NOT NULL DEFAULT 'active'
    CHECK (status IN ('invited', 'active', 'suspended', 'removed'));

-- §10 — domain resolution. normalized_domain is what resolveTenantFromHost()
-- looks up, and it is globally unique: two clinics cannot claim one hostname.
CREATE TABLE app.clinic_domains (
  id                 uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id    uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id          uuid NOT NULL,
  domain             text NOT NULL,
  normalized_domain  text NOT NULL,
  domain_type        text NOT NULL CHECK (domain_type IN ('platform_subdomain', 'custom')),
  verification_token text,
  verified_at        timestamptz,
  status             text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'verification_required', 'verified', 'active', 'suspended', 'removed')),
  is_primary         boolean NOT NULL DEFAULT false,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX clinic_domains_normalized_unique ON app.clinic_domains (normalized_domain);
CREATE INDEX clinic_domains_clinic_idx ON app.clinic_domains (clinic_id);

-- §14 — branding is data, never code. Colours and asset refs only; no CSS, no
-- JS, no arbitrary markup. Validated again in the application before render.
CREATE TABLE app.clinic_branding (
  id                  uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id     uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id           uuid NOT NULL,
  logo_key            text,
  favicon_key         text,
  email_logo_key      text,
  login_background_key text,
  primary_color       text NOT NULL DEFAULT '#12539E' CHECK (primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  secondary_color     text NOT NULL DEFAULT '#0D3F7A' CHECK (secondary_color ~ '^#[0-9A-Fa-f]{6}$'),
  accent_color        text NOT NULL DEFAULT '#2F80ED' CHECK (accent_color ~ '^#[0-9A-Fa-f]{6}$'),
  font_family         text,
  prescription_header text,
  invoice_header      text,
  footer_text         text,
  support_phone       text,
  support_email       text,
  social_links        jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE CASCADE,
  UNIQUE (clinic_id)
);

CREATE TABLE app.clinic_settings (
  id               uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id  uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id        uuid NOT NULL,
  key              text NOT NULL,
  value            jsonb NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE CASCADE,
  UNIQUE (clinic_id, key)
);

-- Profile data for a Better Auth user. The users table itself is created in M2
-- by Better Auth; user_id stays an unconstrained uuid until then (§4.3).
CREATE TABLE app.user_profiles (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  user_id         uuid NOT NULL,
  full_name       text NOT NULL,
  phone           text,
  avatar_key      text,
  preferred_language text NOT NULL DEFAULT 'en',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  UNIQUE (organization_id, user_id)
);

-- §13 — the permission catalogue. Platform-owned, not per-tenant: a clinic
-- cannot invent a permission or grant itself one.
CREATE TABLE app.permissions (
  key         text PRIMARY KEY,
  description text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.roles (
  key           text PRIMARY KEY,
  scope         text NOT NULL CHECK (scope IN ('platform', 'clinic')),
  display_name  text NOT NULL,
  description   text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.role_permissions (
  role_key       text NOT NULL REFERENCES app.roles (key) ON DELETE CASCADE,
  permission_key text NOT NULL REFERENCES app.permissions (key) ON DELETE CASCADE,
  PRIMARY KEY (role_key, permission_key)
);

-- §33 — entitlements, not hard-coded plan logic -------------------------------
CREATE TABLE app.plans (
  id            uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  key           text NOT NULL UNIQUE,
  name          text NOT NULL,
  description   text,
  price_minor   integer NOT NULL DEFAULT 0,
  currency      text NOT NULL DEFAULT 'INR',
  billing_period text NOT NULL DEFAULT 'monthly' CHECK (billing_period IN ('monthly', 'annual')),
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.features (
  key         text PRIMARY KEY,
  name        text NOT NULL,
  unit        text NOT NULL DEFAULT 'boolean' CHECK (unit IN ('boolean', 'count', 'bytes')),
  description text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.plan_features (
  plan_id     uuid NOT NULL REFERENCES app.plans (id) ON DELETE CASCADE,
  feature_key text NOT NULL REFERENCES app.features (key) ON DELETE CASCADE,
  limit_value bigint,
  is_enabled  boolean NOT NULL DEFAULT true,
  PRIMARY KEY (plan_id, feature_key)
);

CREATE TABLE app.subscriptions (
  id                uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id   uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  plan_id           uuid NOT NULL REFERENCES app.plans (id) ON DELETE RESTRICT,
  status            text NOT NULL DEFAULT 'trial'
    CHECK (status IN ('trial', 'active', 'grace_period', 'read_only', 'suspended', 'cancelled')),
  trial_ends_at     timestamptz,
  current_period_start timestamptz,
  current_period_end   timestamptz,
  cancelled_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX subscriptions_org_idx ON app.subscriptions (organization_id);

-- Resolved entitlement per organization. Denormalised from plan_features on
-- purpose: a plan changing must never silently alter what a paying clinic
-- already has, and an override needs somewhere to live.
CREATE TABLE app.entitlements (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  feature_key     text NOT NULL REFERENCES app.features (key) ON DELETE RESTRICT,
  limit_value     bigint,
  is_enabled      boolean NOT NULL DEFAULT true,
  source          text NOT NULL DEFAULT 'plan' CHECK (source IN ('plan', 'override')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, feature_key)
);

-- §34 — usage tracking from the beginning, even while billing is simple.
CREATE TABLE app.usage_events (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  feature_key     text NOT NULL REFERENCES app.features (key) ON DELETE RESTRICT,
  quantity        bigint NOT NULL DEFAULT 1,
  metadata        jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at     timestamptz NOT NULL DEFAULT now(),
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX usage_events_org_feature_idx ON app.usage_events (organization_id, feature_key, occurred_at);

CREATE TABLE app.usage_counters (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  feature_key     text NOT NULL REFERENCES app.features (key) ON DELETE RESTRICT,
  period_start    date NOT NULL,
  period_end      date NOT NULL,
  used            bigint NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, feature_key, period_start)
);

CREATE TABLE app.feature_flags (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  key             text NOT NULL,
  is_enabled      boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, key)
);

-- =============================================================================
-- 5. Clinical
-- =============================================================================
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE app.doctors (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  user_id         uuid,
  full_name       text NOT NULL,
  specialty       text,
  qualifications  text,
  -- §21 and the prescription legal review: a prescription carries a registered
  -- practitioner's identity, and the registration number belongs on it.
  registration_number text,
  phone           text,
  email           text,
  photo_key       text,
  bio             text,
  consultation_fee_minor integer,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);
CREATE INDEX doctors_org_idx ON app.doctors (organization_id) WHERE deleted_at IS NULL;

-- §35 — a doctor may work at several locations.
CREATE TABLE app.doctor_clinics (
  organization_id uuid NOT NULL,
  doctor_id       uuid NOT NULL REFERENCES app.doctors (id) ON DELETE CASCADE,
  clinic_id       uuid NOT NULL,
  PRIMARY KEY (doctor_id, clinic_id),
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE CASCADE
);

CREATE TABLE app.staff (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  user_id         uuid,
  full_name       text NOT NULL,
  job_title       text,
  phone           text,
  email           text,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE SET NULL
);

CREATE TABLE app.services (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  name            text NOT NULL,
  description     text,
  duration_minutes integer NOT NULL DEFAULT 15,
  price_minor     integer,
  -- §22 and the GST question: tax treatment belongs on the line, not the clinic.
  -- Clinical services are largely GST-exempt in India while aesthetics, dental
  -- procedures, and pharmacy sales are not, so a per-clinic rate would produce
  -- wrong invoices. "exempt" is a distinct state from a 0% rate: they print
  -- differently on a compliant invoice.
  tax_treatment   text NOT NULL DEFAULT 'exempt'
    CHECK (tax_treatment IN ('exempt', 'nil_rated', 'taxable')),
  tax_rate_bp     integer NOT NULL DEFAULT 0 CHECK (tax_rate_bp BETWEEN 0 AND 10000),
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE SET NULL,
  CHECK (tax_treatment <> 'taxable' OR tax_rate_bp > 0)
);

-- Extend the spike patients table --------------------------------------------
ALTER TABLE app.patients
  ADD COLUMN patient_code   text,
  ADD COLUMN email          text,
  ADD COLUMN date_of_birth  date,
  ADD COLUMN gender         text CHECK (gender IN ('female', 'male', 'other', 'undisclosed')),
  ADD COLUMN blood_group    text,
  ADD COLUMN address_line1  text,
  ADD COLUMN address_line2  text,
  ADD COLUMN city           text,
  ADD COLUMN state          text,
  ADD COLUMN postal_code    text,
  -- §23.1, §32 — the language a patient is spoken to in. Stored from day one so
  -- patient-facing localisation is additive rather than a migration.
  ADD COLUMN preferred_language text NOT NULL DEFAULT 'en',
  ADD COLUMN status         text NOT NULL DEFAULT 'active'
    CHECK (status IN ('lead', 'prospect', 'active', 'inactive', 'reactivation_candidate')),
  ADD COLUMN first_visit_at timestamptz,
  ADD COLUMN last_visit_at  timestamptz,
  ADD COLUMN source         text,
  ADD CONSTRAINT patients_code_unique UNIQUE (organization_id, patient_code);

CREATE TABLE app.patient_consents (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  patient_id      uuid NOT NULL REFERENCES app.patients (id) ON DELETE RESTRICT,
  consent_type    text NOT NULL,
  granted         boolean NOT NULL,
  granted_at      timestamptz,
  revoked_at      timestamptz,
  source          text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX patient_consents_patient_idx ON app.patient_consents (patient_id);

-- §37 — object_key is a tenant-scoped R2 path. Files are always fetched through
-- a short-lived signed URL; there is no permanent public URL for these.
CREATE TABLE app.patient_documents (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  patient_id      uuid NOT NULL REFERENCES app.patients (id) ON DELETE RESTRICT,
  uploaded_by     uuid,
  title           text NOT NULL,
  document_type   text,
  object_key      text NOT NULL,
  content_type    text NOT NULL,
  size_bytes      bigint NOT NULL,
  checksum        text,
  scan_status     text NOT NULL DEFAULT 'pending'
    CHECK (scan_status IN ('pending', 'clean', 'infected', 'skipped')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);
CREATE INDEX patient_documents_patient_idx ON app.patient_documents (patient_id) WHERE deleted_at IS NULL;

CREATE TABLE app.medical_history (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  patient_id      uuid NOT NULL REFERENCES app.patients (id) ON DELETE RESTRICT,
  recorded_by     uuid,
  summary         text NOT NULL,
  details         text,
  recorded_at     timestamptz NOT NULL DEFAULT now(),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);
CREATE INDEX medical_history_patient_idx ON app.medical_history (patient_id) WHERE deleted_at IS NULL;

CREATE TABLE app.allergies (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  patient_id      uuid NOT NULL REFERENCES app.patients (id) ON DELETE RESTRICT,
  substance       text NOT NULL,
  severity        text CHECK (severity IN ('mild', 'moderate', 'severe')),
  reaction        text,
  noted_at        timestamptz NOT NULL DEFAULT now(),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);
CREATE INDEX allergies_patient_idx ON app.allergies (patient_id) WHERE deleted_at IS NULL;

CREATE TABLE app.appointment_types (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  name            text NOT NULL,
  duration_minutes integer NOT NULL DEFAULT 15,
  colour          text,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE SET NULL
);

CREATE TABLE app.doctor_availability (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid NOT NULL,
  doctor_id       uuid NOT NULL REFERENCES app.doctors (id) ON DELETE CASCADE,
  weekday         smallint CHECK (weekday BETWEEN 0 AND 6),
  starts_time     time,
  ends_time       time,
  effective_from  date,
  effective_to    date,
  kind            text NOT NULL DEFAULT 'working'
    CHECK (kind IN ('working', 'break', 'holiday')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE CASCADE,
  CHECK (starts_time IS NULL OR ends_time IS NULL OR starts_time < ends_time)
);
CREATE INDEX doctor_availability_doctor_idx ON app.doctor_availability (doctor_id, weekday);

-- §18 — "Prevent double booking under concurrent submissions using
-- database-level protection." Application-side checking loses the race by
-- construction: two requests both read "free" before either writes. The EXCLUDE
-- constraint below is the only thing that actually holds under concurrency.
CREATE TABLE app.appointments (
  id                 uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id    uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id          uuid NOT NULL,
  patient_id         uuid NOT NULL REFERENCES app.patients (id) ON DELETE RESTRICT,
  doctor_id          uuid NOT NULL REFERENCES app.doctors (id) ON DELETE RESTRICT,
  appointment_type_id uuid REFERENCES app.appointment_types (id) ON DELETE SET NULL,
  service_id         uuid REFERENCES app.services (id) ON DELETE SET NULL,
  starts_at          timestamptz NOT NULL,
  ends_at            timestamptz NOT NULL,
  status             text NOT NULL DEFAULT 'booked'
    CHECK (status IN ('booked', 'confirmed', 'cancelled', 'completed', 'no_show', 'waitlisted')),
  booking_source     text,
  notes              text,
  cancelled_at       timestamptz,
  cancellation_reason text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  deleted_at         timestamptz,
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT,
  CHECK (ends_at > starts_at),
  CONSTRAINT appointments_no_double_booking
    EXCLUDE USING gist (
      doctor_id WITH =,
      tstzrange(starts_at, ends_at) WITH &&
    ) WHERE (status IN ('booked', 'confirmed') AND deleted_at IS NULL)
);
CREATE INDEX appointments_clinic_date_idx ON app.appointments (clinic_id, starts_at) WHERE deleted_at IS NULL;
CREATE INDEX appointments_patient_idx ON app.appointments (patient_id) WHERE deleted_at IS NULL;
CREATE INDEX appointments_doctor_date_idx ON app.appointments (doctor_id, starts_at) WHERE deleted_at IS NULL;

CREATE TABLE app.consultation_notes (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  patient_id      uuid NOT NULL REFERENCES app.patients (id) ON DELETE RESTRICT,
  appointment_id  uuid REFERENCES app.appointments (id) ON DELETE SET NULL,
  doctor_id       uuid NOT NULL REFERENCES app.doctors (id) ON DELETE RESTRICT,
  complaint       text,
  examination     text,
  diagnosis       text,
  advice          text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);
CREATE INDEX consultation_notes_patient_idx ON app.consultation_notes (patient_id) WHERE deleted_at IS NULL;

CREATE TABLE app.prescriptions (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid NOT NULL,
  patient_id      uuid NOT NULL REFERENCES app.patients (id) ON DELETE RESTRICT,
  doctor_id       uuid NOT NULL REFERENCES app.doctors (id) ON DELETE RESTRICT,
  appointment_id  uuid REFERENCES app.appointments (id) ON DELETE SET NULL,
  prescription_number text,
  notes           text,
  issued_at       timestamptz NOT NULL DEFAULT now(),
  pdf_object_key  text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, prescription_number)
);
CREATE INDEX prescriptions_patient_idx ON app.prescriptions (patient_id) WHERE deleted_at IS NULL;

CREATE TABLE app.prescription_items (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  prescription_id uuid NOT NULL REFERENCES app.prescriptions (id) ON DELETE CASCADE,
  medicine_name   text NOT NULL,
  dosage          text,
  frequency       text,
  duration        text,
  instructions    text,
  sort_order      integer NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX prescription_items_prescription_idx ON app.prescription_items (prescription_id);

-- =============================================================================
-- 6. Family Health Graph (§6, §7)
--
-- §7.2: "Do not defer households, patient_household_links, and health_conditions
-- to Phase 2 - they must be in the first migration, even though the UI built on
-- top of them ships later. This is the single most important 'don't do this
-- later, do it now' instruction in this document."
--
-- The reason is mechanical, not stylistic. condition_timeline_events tags an
-- event with the condition it belongs to at the moment the event happens. That
-- link cannot be reconstructed afterwards from a flat feed without a clinician
-- re-reading every record, so deferring the tables means the data is simply
-- lost for every visit that happens before they exist.
--
-- A household is a GROUPING construct and never a security boundary (§6). It
-- gets the same organization_id policy as everything else, and membership grants
-- no cross-patient read: a parent does not see a spouse's record by virtue of
-- sharing a household. Family access on the portal is separate and consent-gated.
-- =============================================================================

CREATE TABLE app.households (
  id                        uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id           uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id                 uuid NOT NULL,
  name                      text,
  primary_contact_patient_id uuid,
  address_line1             text,
  address_line2             text,
  city                      text,
  state                     text,
  postal_code               text,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  deleted_at                timestamptz,
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT
);
CREATE INDEX households_org_idx ON app.households (organization_id) WHERE deleted_at IS NULL;

CREATE TABLE app.patient_household_links (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  patient_id      uuid NOT NULL REFERENCES app.patients (id) ON DELETE CASCADE,
  household_id    uuid NOT NULL REFERENCES app.households (id) ON DELETE CASCADE,
  relationship    text NOT NULL
    CHECK (relationship IN ('self', 'spouse', 'child', 'parent', 'dependent')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  UNIQUE (patient_id, household_id)
);
CREATE INDEX patient_household_links_household_idx ON app.patient_household_links (household_id);
CREATE INDEX patient_household_links_patient_idx ON app.patient_household_links (patient_id);

-- A household's primary contact must be a patient in that household. Added
-- after both tables exist because the reference is circular.
ALTER TABLE app.households
  ADD CONSTRAINT households_primary_contact_fk
  FOREIGN KEY (primary_contact_patient_id) REFERENCES app.patients (id) ON DELETE SET NULL;

-- §6 — condition_code uses ICD-10 "where feasible". Stored as free text plus an
-- explicit system column rather than a hard FK to an ICD-10 table: a doctor with
-- five minutes per patient will not search seventy thousand codes, so the UI is
-- driven by a curated per-specialty shortlist that maps onto this column. That
-- same shortlist is what §32.8 needs at content-onboarding time.
CREATE TABLE app.health_conditions (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  patient_id      uuid NOT NULL REFERENCES app.patients (id) ON DELETE RESTRICT,
  condition_code  text,
  code_system     text NOT NULL DEFAULT 'icd10' CHECK (code_system IN ('icd10', 'local')),
  display_name    text NOT NULL,
  status          text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'resolved', 'chronic', 'monitoring')),
  diagnosed_at    timestamptz,
  diagnosed_by    uuid REFERENCES app.doctors (id) ON DELETE SET NULL,
  resolved_at     timestamptz,
  notes           text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);
CREATE INDEX health_conditions_patient_idx ON app.health_conditions (patient_id) WHERE deleted_at IS NULL;
CREATE INDEX health_conditions_code_idx ON app.health_conditions (organization_id, condition_code);

-- §17 — the unified patient timeline.
CREATE TABLE app.patient_timeline_events (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  patient_id      uuid NOT NULL REFERENCES app.patients (id) ON DELETE CASCADE,
  event_type      text NOT NULL,
  occurred_at     timestamptz NOT NULL DEFAULT now(),
  actor_user_id   uuid,
  summary         text,
  metadata        jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX patient_timeline_patient_idx ON app.patient_timeline_events (patient_id, occurred_at DESC);

-- §6, §17 — the join that turns a flat chronological feed into "show me
-- everything related to this patient's diabetes". This is the table that cannot
-- be backfilled, and therefore the reason the whole graph ships now.
CREATE TABLE app.condition_timeline_events (
  id                  uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id     uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  health_condition_id uuid NOT NULL REFERENCES app.health_conditions (id) ON DELETE CASCADE,
  timeline_event_id   uuid NOT NULL REFERENCES app.patient_timeline_events (id) ON DELETE CASCADE,
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (health_condition_id, timeline_event_id)
);
CREATE INDEX condition_timeline_condition_idx ON app.condition_timeline_events (health_condition_id);

-- §6, §28 — "computed, never fabricated". The calculation that produced a flag
-- is stored alongside it, so an insight can always be explained and audited.
-- Phase 1 creates the table and the write path; no UI surfaces it yet.
CREATE TABLE app.family_recurrence_flags (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  household_id    uuid NOT NULL REFERENCES app.households (id) ON DELETE CASCADE,
  signal_type     text NOT NULL,
  summary         text NOT NULL,
  calculation     jsonb NOT NULL,
  member_count    integer NOT NULL,
  window_days     integer NOT NULL,
  computed_at     timestamptz NOT NULL DEFAULT now(),
  acknowledged_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX family_recurrence_household_idx ON app.family_recurrence_flags (household_id, computed_at DESC);

-- =============================================================================
-- 7. Commercial (§22)
-- =============================================================================
CREATE TABLE app.invoices (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid NOT NULL,
  patient_id      uuid NOT NULL REFERENCES app.patients (id) ON DELETE RESTRICT,
  appointment_id  uuid REFERENCES app.appointments (id) ON DELETE SET NULL,
  invoice_number  text NOT NULL,
  status          text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'issued', 'partially_paid', 'paid', 'void', 'refunded')),
  subtotal_minor  integer NOT NULL DEFAULT 0,
  discount_minor  integer NOT NULL DEFAULT 0,
  tax_minor       integer NOT NULL DEFAULT 0,
  total_minor     integer NOT NULL DEFAULT 0,
  amount_paid_minor integer NOT NULL DEFAULT 0,
  currency        text NOT NULL DEFAULT 'INR',
  issued_at       timestamptz,
  due_at          timestamptz,
  pdf_object_key  text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, invoice_number)
);
CREATE INDEX invoices_patient_idx ON app.invoices (patient_id) WHERE deleted_at IS NULL;
CREATE INDEX invoices_status_idx ON app.invoices (organization_id, status);

CREATE TABLE app.invoice_items (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  invoice_id      uuid NOT NULL REFERENCES app.invoices (id) ON DELETE CASCADE,
  service_id      uuid REFERENCES app.services (id) ON DELETE SET NULL,
  description     text NOT NULL,
  quantity        integer NOT NULL DEFAULT 1,
  unit_price_minor integer NOT NULL DEFAULT 0,
  discount_minor  integer NOT NULL DEFAULT 0,
  -- Per-line, per §22's GST question. Exempt is not a 0% rate.
  tax_treatment   text NOT NULL DEFAULT 'exempt'
    CHECK (tax_treatment IN ('exempt', 'nil_rated', 'taxable')),
  tax_rate_bp     integer NOT NULL DEFAULT 0 CHECK (tax_rate_bp BETWEEN 0 AND 10000),
  tax_minor       integer NOT NULL DEFAULT 0,
  total_minor     integer NOT NULL DEFAULT 0,
  sort_order      integer NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX invoice_items_invoice_idx ON app.invoice_items (invoice_id);

CREATE TABLE app.payments (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  invoice_id      uuid REFERENCES app.invoices (id) ON DELETE SET NULL,
  patient_id      uuid NOT NULL REFERENCES app.patients (id) ON DELETE RESTRICT,
  amount_minor    integer NOT NULL,
  currency        text NOT NULL DEFAULT 'INR',
  method          text NOT NULL CHECK (method IN ('cash', 'card', 'upi', 'netbanking', 'wallet', 'other')),
  status          text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'succeeded', 'failed', 'refunded')),
  received_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX payments_invoice_idx ON app.payments (invoice_id);

-- §22, §53 — provider_event_id is UNIQUE so replaying a webhook cannot double
-- count a payment. Idempotency enforced by the database, not by application
-- bookkeeping that a retry can race.
CREATE TABLE app.payment_transactions (
  id                 uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id    uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  payment_id         uuid REFERENCES app.payments (id) ON DELETE SET NULL,
  provider           text NOT NULL,
  provider_order_id  text,
  provider_payment_id text,
  provider_event_id  text NOT NULL,
  event_type         text NOT NULL,
  amount_minor       integer,
  signature_verified boolean NOT NULL DEFAULT false,
  raw_payload        jsonb NOT NULL,
  processed_at       timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_event_id)
);

CREATE TABLE app.discounts (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  code            text,
  name            text NOT NULL,
  kind            text NOT NULL CHECK (kind IN ('percentage', 'fixed')),
  value_bp        integer,
  value_minor     integer,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.taxes (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  name            text NOT NULL,
  rate_bp         integer NOT NULL CHECK (rate_bp BETWEEN 0 AND 10000),
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- 8. Growth (§16, §17, §29)
-- =============================================================================
CREATE TABLE app.lead_sources (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  key             text NOT NULL,
  name            text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, key)
);

CREATE TABLE app.leads (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  patient_id      uuid REFERENCES app.patients (id) ON DELETE SET NULL,
  full_name       text NOT NULL,
  phone           text,
  email           text,
  message         text,
  status          text NOT NULL DEFAULT 'new'
    CHECK (status IN ('new', 'contacted', 'qualified', 'appointment_booked', 'converted', 'lost')),
  assigned_to     uuid,
  -- §29 — attribution captured at capture time and never rewritten.
  utm_source      text,
  utm_medium      text,
  utm_campaign    text,
  utm_content     text,
  referrer        text,
  landing_page    text,
  source_key      text,
  consent_given   boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE SET NULL
);
CREATE INDEX leads_status_idx ON app.leads (organization_id, status) WHERE deleted_at IS NULL;
CREATE INDEX leads_phone_idx ON app.leads (organization_id, phone);

CREATE TABLE app.lead_events (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  lead_id         uuid NOT NULL REFERENCES app.leads (id) ON DELETE CASCADE,
  event_type      text NOT NULL,
  actor_user_id   uuid,
  notes           text,
  occurred_at     timestamptz NOT NULL DEFAULT now(),
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX lead_events_lead_idx ON app.lead_events (lead_id, occurred_at DESC);

CREATE TABLE app.referral_sources (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  name            text NOT NULL,
  kind            text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.followups (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  patient_id      uuid NOT NULL REFERENCES app.patients (id) ON DELETE CASCADE,
  appointment_id  uuid REFERENCES app.appointments (id) ON DELETE SET NULL,
  health_condition_id uuid REFERENCES app.health_conditions (id) ON DELETE SET NULL,
  assigned_to     uuid,
  due_at          timestamptz NOT NULL,
  reason          text,
  status          text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'completed', 'cancelled', 'overdue')),
  completed_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);
CREATE INDEX followups_due_idx ON app.followups (organization_id, status, due_at) WHERE deleted_at IS NULL;

CREATE TABLE app.campaigns (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  name            text NOT NULL,
  channel         text NOT NULL CHECK (channel IN ('whatsapp', 'sms', 'email')),
  status          text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'scheduled', 'running', 'completed', 'cancelled')),
  scheduled_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.campaign_recipients (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  campaign_id     uuid NOT NULL REFERENCES app.campaigns (id) ON DELETE CASCADE,
  patient_id      uuid NOT NULL REFERENCES app.patients (id) ON DELETE CASCADE,
  status          text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'sent', 'failed', 'skipped_opt_out')),
  sent_at         timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (campaign_id, patient_id)
);

CREATE TABLE app.reviews (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  patient_id      uuid REFERENCES app.patients (id) ON DELETE SET NULL,
  rating          smallint CHECK (rating BETWEEN 1 AND 5),
  comment         text,
  requested_at    timestamptz,
  submitted_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- 9. Communication (§24, §25)
-- =============================================================================
CREATE TABLE app.communication_templates (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  key             text NOT NULL,
  channel         text NOT NULL CHECK (channel IN ('whatsapp', 'sms', 'email')),
  language        text NOT NULL DEFAULT 'en',
  subject         text,
  body            text NOT NULL,
  provider_template_name text,
  status          text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'pending_approval', 'approved', 'rejected')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, key, channel, language)
);

-- §24 — one shape per channel, all carrying the same delivery lifecycle.
CREATE TABLE app.whatsapp_messages (
  id                  uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id     uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id           uuid,
  patient_id          uuid REFERENCES app.patients (id) ON DELETE SET NULL,
  template_key        text,
  to_number           text NOT NULL,
  body                text,
  provider            text,
  provider_message_id text,
  status              text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'sent', 'delivered', 'read', 'failed')),
  error               text,
  sent_at             timestamptz,
  delivered_at        timestamptz,
  read_at             timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX whatsapp_messages_patient_idx ON app.whatsapp_messages (patient_id, created_at DESC);

CREATE TABLE app.sms_messages (
  id                  uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id     uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id           uuid,
  patient_id          uuid REFERENCES app.patients (id) ON DELETE SET NULL,
  template_key        text,
  to_number           text NOT NULL,
  body                text NOT NULL,
  provider            text,
  provider_message_id text,
  status              text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'sent', 'delivered', 'failed')),
  error               text,
  sent_at             timestamptz,
  delivered_at        timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.email_messages (
  id                  uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id     uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id           uuid,
  patient_id          uuid REFERENCES app.patients (id) ON DELETE SET NULL,
  template_key        text,
  to_email            text NOT NULL,
  subject             text NOT NULL,
  body_html           text,
  provider            text,
  provider_message_id text,
  status              text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'sent', 'delivered', 'bounced', 'failed')),
  error               text,
  sent_at             timestamptz,
  delivered_at        timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.communication_preferences (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  patient_id      uuid NOT NULL REFERENCES app.patients (id) ON DELETE CASCADE,
  channel         text NOT NULL CHECK (channel IN ('whatsapp', 'sms', 'email')),
  is_enabled      boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (patient_id, channel)
);

-- §24 — opt-out is checked before every send. Kept in its own table rather than
-- a flag on the patient so a revoked consent survives a patient record merge.
CREATE TABLE app.opt_outs (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  patient_id      uuid REFERENCES app.patients (id) ON DELETE SET NULL,
  channel         text NOT NULL CHECK (channel IN ('whatsapp', 'sms', 'email')),
  contact_value   text NOT NULL,
  reason          text,
  opted_out_at    timestamptz NOT NULL DEFAULT now(),
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, channel, contact_value)
);

-- =============================================================================
-- 10. Events and automation (§26, §27)
-- =============================================================================

-- Transactional outbox. Written in the SAME transaction as the state change it
-- describes, so an event can never exist for a change that rolled back, nor be
-- lost for one that committed. Drained by a worker claiming rows with
-- FOR UPDATE SKIP LOCKED, which is what makes the move to a real queue later a
-- change of consumer rather than a change of design (§26).
CREATE TABLE app.domain_events (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  event_type      text NOT NULL,
  aggregate_type  text NOT NULL,
  aggregate_id    uuid NOT NULL,
  payload         jsonb NOT NULL DEFAULT '{}'::jsonb,
  status          text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'processed', 'failed', 'dead')),
  attempts        integer NOT NULL DEFAULT 0,
  last_error      text,
  available_at    timestamptz NOT NULL DEFAULT now(),
  processed_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX domain_events_pending_idx ON app.domain_events (status, available_at)
  WHERE status IN ('pending', 'failed');

CREATE TABLE app.automation_templates (
  key         text PRIMARY KEY,
  name        text NOT NULL,
  description text,
  definition  jsonb NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.automation_rules (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  name            text NOT NULL,
  template_key    text REFERENCES app.automation_templates (key) ON DELETE SET NULL,
  is_enabled      boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE app.automation_triggers (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  rule_id         uuid NOT NULL REFERENCES app.automation_rules (id) ON DELETE CASCADE,
  event_type      text NOT NULL,
  conditions      jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.automation_actions (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  rule_id         uuid NOT NULL REFERENCES app.automation_rules (id) ON DELETE CASCADE,
  action_type     text NOT NULL,
  config          jsonb NOT NULL DEFAULT '{}'::jsonb,
  sort_order      integer NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- §27 — "idempotent, auditable, retryable, rate limited, tenant scoped".
-- idempotency_key is UNIQUE, so a retry of the same trigger for the same
-- aggregate cannot execute twice however many times the worker redelivers.
CREATE TABLE app.automation_runs (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  rule_id         uuid NOT NULL REFERENCES app.automation_rules (id) ON DELETE CASCADE,
  domain_event_id uuid REFERENCES app.domain_events (id) ON DELETE SET NULL,
  idempotency_key text NOT NULL,
  status          text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'running', 'succeeded', 'failed', 'skipped')),
  attempts        integer NOT NULL DEFAULT 0,
  last_error      text,
  started_at      timestamptz,
  finished_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, idempotency_key)
);

-- =============================================================================
-- 11. Website studio (§15)
-- =============================================================================
CREATE TABLE app.website_templates (
  key         text PRIMARY KEY,
  name        text NOT NULL,
  specialty   text,
  definition  jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.websites (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid NOT NULL,
  template_key    text REFERENCES app.website_templates (key) ON DELETE SET NULL,
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published')),
  seo_title       text,
  seo_description text,
  og_image_key    text,
  published_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, clinic_id) REFERENCES app.clinics (organization_id, id) ON DELETE CASCADE,
  UNIQUE (clinic_id)
);

CREATE TABLE app.website_sections (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  website_id      uuid NOT NULL REFERENCES app.websites (id) ON DELETE CASCADE,
  section_type    text NOT NULL,
  content         jsonb NOT NULL DEFAULT '{}'::jsonb,
  sort_order      integer NOT NULL DEFAULT 0,
  is_visible      boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX website_sections_website_idx ON app.website_sections (website_id, sort_order);

-- =============================================================================
-- 12. Platform (§39, §43)
-- =============================================================================
CREATE TABLE app.audit_logs (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  actor_user_id   uuid,
  action          text NOT NULL,
  entity_type     text NOT NULL,
  entity_id       uuid,
  -- §39 — set when a platform admin acted inside a tenant. withPlatformAdmin()
  -- takes a reason precisely so this column is never null for such an action.
  impersonation_reason text,
  before_state    jsonb,
  after_state     jsonb,
  ip_address      inet,
  user_agent      text,
  occurred_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_logs_org_idx ON app.audit_logs (organization_id, occurred_at DESC);
CREATE INDEX audit_logs_entity_idx ON app.audit_logs (entity_type, entity_id);

CREATE TABLE app.access_logs (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  actor_user_id   uuid,
  resource_type   text NOT NULL,
  resource_id     uuid,
  action          text NOT NULL,
  ip_address      inet,
  occurred_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX access_logs_org_idx ON app.access_logs (organization_id, occurred_at DESC);

CREATE TABLE app.integration_connections (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  clinic_id       uuid,
  provider        text NOT NULL,
  status          text NOT NULL DEFAULT 'disconnected'
    CHECK (status IN ('disconnected', 'connected', 'error')),
  config          jsonb NOT NULL DEFAULT '{}'::jsonb,
  connected_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, provider)
);

CREATE TABLE app.webhooks (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid NOT NULL REFERENCES app.organizations (id) ON DELETE RESTRICT,
  provider        text NOT NULL,
  endpoint        text NOT NULL,
  secret_ref      text,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.error_events (
  id              uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  organization_id uuid REFERENCES app.organizations (id) ON DELETE SET NULL,
  request_id      text,
  job_id          text,
  level           text NOT NULL DEFAULT 'error' CHECK (level IN ('warn', 'error', 'fatal')),
  message         text NOT NULL,
  context         jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.system_events (
  id          uuid PRIMARY KEY DEFAULT app.uuid_v7(),
  event_type  text NOT NULL,
  payload     jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- 13. Apply Row Level Security
--
-- Applied from lists rather than written out per table. Sixty-plus hand-written
-- policies would be sixty-plus chances to write a subtly weaker one, and a
-- reviewer cannot eyeball that they are all identical. Here they are identical
-- by construction, and the test suite asserts that EVERY table in the schema
-- ends up with RLS enabled and forced -- so a table added later without being
-- listed here fails the build rather than shipping unprotected.
--
-- organizations, clinics, clinic_users, patients, and platform_admins already
-- carry their policies from migration 0001 and are deliberately absent below.
-- =============================================================================
DO $$
DECLARE
  t text;
  tenant_tables text[] := ARRAY[
    'clinic_domains','clinic_branding','clinic_settings','user_profiles',
    'subscriptions','entitlements','usage_events','usage_counters','feature_flags',
    'doctors','doctor_clinics','staff','services',
    'patient_consents','patient_documents','medical_history','allergies',
    'appointment_types','doctor_availability','appointments','consultation_notes',
    'prescriptions','prescription_items',
    'households','patient_household_links','health_conditions',
    'patient_timeline_events','condition_timeline_events','family_recurrence_flags',
    'invoices','invoice_items','payments','payment_transactions','discounts','taxes',
    'lead_sources','leads','lead_events','referral_sources','followups',
    'campaigns','campaign_recipients','reviews',
    'communication_templates','whatsapp_messages','sms_messages','email_messages',
    'communication_preferences','opt_outs',
    'domain_events','automation_rules','automation_triggers','automation_actions','automation_runs',
    'websites','website_sections',
    'audit_logs','access_logs','integration_connections','webhooks','error_events'
  ];
  catalog_tables text[] := ARRAY[
    'permissions','roles','role_permissions',
    'plans','features','plan_features',
    'automation_templates','website_templates'
  ];
  platform_tables text[] := ARRAY['system_events'];
BEGIN
  FOREACH t IN ARRAY tenant_tables   LOOP CALL app.apply_tenant_rls(t);   END LOOP;
  FOREACH t IN ARRAY catalog_tables  LOOP CALL app.apply_catalog_rls(t);  END LOOP;
  FOREACH t IN ARRAY platform_tables LOOP CALL app.apply_platform_rls(t); END LOOP;
END
$$;

-- =============================================================================
-- 14. updated_at triggers, applied to every table that has the column
-- =============================================================================
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid
     WHERE n.nspname = 'app'
       AND c.relkind = 'r'
       AND a.attname = 'updated_at'
       AND NOT a.attisdropped
  LOOP
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE ON app.%I
         FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at()',
      r.relname || '_touch', r.relname
    );
  END LOOP;
END
$$;

-- =============================================================================
-- 15. Grants for the new tables
-- =============================================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO clinic_os_app;
GRANT EXECUTE ON FUNCTION app.uuid_v7() TO clinic_os_app;

-- =============================================================================
-- 16. Platform catalogue seed (§13, §33)
--
-- Not tenant data. These are the roles, permissions, and plans the platform
-- itself defines; a clinic can neither invent nor grant them.
-- =============================================================================
INSERT INTO app.permissions (key, description) VALUES
  ('patients.read','View patients'),
  ('patients.create','Create patients'),
  ('patients.update','Update patients'),
  ('patients.delete','Delete patients'),
  ('appointments.read','View appointments'),
  ('appointments.create','Create appointments'),
  ('appointments.update','Update appointments'),
  ('appointments.cancel','Cancel appointments'),
  ('prescriptions.read','View prescriptions'),
  ('prescriptions.create','Create prescriptions'),
  ('billing.read','View billing'),
  ('billing.create','Create invoices and record payments'),
  ('billing.refund','Issue refunds'),
  ('staff.manage','Manage staff and doctors'),
  ('branding.manage','Manage clinic branding'),
  ('domain.manage','Manage custom domains'),
  ('analytics.read','View analytics'),
  ('campaigns.manage','Manage campaigns'),
  ('automation.manage','Manage automation rules'),
  ('health_graph.read','View households and conditions'),
  ('health_graph.manage','Manage households and conditions');

INSERT INTO app.roles (key, scope, display_name, description) VALUES
  ('platform_owner','platform','Platform Owner','Full platform access'),
  ('platform_admin','platform','Platform Admin','Platform administration'),
  ('clinic_owner','clinic','Clinic Owner','Full access within the clinic'),
  ('clinic_admin','clinic','Clinic Admin','Clinic administration'),
  ('doctor','clinic','Doctor','Consultation and clinical records'),
  ('receptionist','clinic','Receptionist','Front desk and scheduling'),
  ('accountant','clinic','Accountant','Billing and payments'),
  ('nurse','clinic','Nurse','Clinical support'),
  ('read_only_staff','clinic','Read-only Staff','View access only');

-- §13 — permission-based, not role-name checks scattered through the code.
INSERT INTO app.role_permissions (role_key, permission_key)
SELECT 'clinic_owner', key FROM app.permissions;

INSERT INTO app.role_permissions (role_key, permission_key)
SELECT 'clinic_admin', key FROM app.permissions WHERE key <> 'billing.refund';

INSERT INTO app.role_permissions (role_key, permission_key) VALUES
  ('doctor','patients.read'),('doctor','patients.update'),
  ('doctor','appointments.read'),('doctor','appointments.update'),
  ('doctor','prescriptions.read'),('doctor','prescriptions.create'),
  ('doctor','health_graph.read'),('doctor','health_graph.manage'),
  ('receptionist','patients.read'),('receptionist','patients.create'),('receptionist','patients.update'),
  ('receptionist','appointments.read'),('receptionist','appointments.create'),
  ('receptionist','appointments.update'),('receptionist','appointments.cancel'),
  ('receptionist','billing.read'),('receptionist','billing.create'),
  ('receptionist','health_graph.read'),
  ('accountant','billing.read'),('accountant','billing.create'),('accountant','billing.refund'),
  ('accountant','analytics.read'),
  ('nurse','patients.read'),('nurse','appointments.read'),('nurse','health_graph.read'),
  ('read_only_staff','patients.read'),('read_only_staff','appointments.read'),
  ('read_only_staff','billing.read');

INSERT INTO app.features (key, name, unit, description) VALUES
  ('doctors','Doctors','count','Number of doctors'),
  ('staff','Staff members','count','Number of staff users'),
  ('locations','Locations','count','Number of clinic locations'),
  ('storage_bytes','Storage','bytes','Document storage'),
  ('whatsapp_messages','WhatsApp messages','count','Monthly WhatsApp sends'),
  ('sms_messages','SMS messages','count','Monthly SMS sends'),
  ('email_messages','Emails','count','Monthly email sends'),
  ('ai_requests','AI requests','count','Monthly AI usage'),
  ('website','Clinic website','boolean','Website studio'),
  ('crm','Patient CRM','boolean','CRM and timeline'),
  ('automation','Automation','boolean','Automation engine'),
  ('analytics','Analytics','boolean','Growth dashboard'),
  ('custom_domain','Custom domain','boolean','Bring your own domain'),
  ('white_label','White label','boolean','Full white labelling'),
  ('api_access','API access','boolean','API platform'),
  ('sso','SSO','boolean','Single sign-on'),
  -- §32.7 — declared now so Phase 2 is an entitlement flip, not a schema change.
  ('education_sessions','Visual education sessions','count','Visual Health Advisor sessions');

INSERT INTO app.plans (key, name, description, price_minor, billing_period) VALUES
  ('core','Core','Run the clinic', 0, 'monthly'),
  ('growth','Growth','Run and grow the clinic', 0, 'monthly'),
  ('white_label','White Label','Fully branded', 0, 'monthly'),
  ('enterprise','Enterprise','Multi-location and API', 0, 'monthly');

INSERT INTO app.website_templates (key, name, specialty) VALUES
  ('general_physician','General Physician','general_physician'),
  ('dental','Dental','dental'),
  ('dermatology','Dermatology','dermatology'),
  ('orthopaedic','Orthopaedic','orthopaedic'),
  ('paediatric','Paediatric','paediatric'),
  ('gynaecology','Gynaecology','gynaecology'),
  ('physiotherapy','Physiotherapy','physiotherapy'),
  ('ayurveda','Ayurveda','ayurveda'),
  ('psychology','Psychology','psychology'),
  ('fertility','Fertility','fertility'),
  ('aesthetic','Aesthetic','aesthetic');

-- =============================================================================
-- 17. Cross-tenant foreign keys
--
-- Foreign key validation runs with the constraint's own privileges and does NOT
-- go through Row Level Security. A single-column FK to a tenant-owned parent is
-- therefore a hole in the boundary, in two ways:
--
--   1. Clinic A can insert a row referencing Clinic B's patient, household, or
--      appointment id. RLS accepts the row -- its own organization_id is A's --
--      and the FK accepts the reference, so a genuine cross-tenant link exists.
--   2. It is an existence oracle. A valid id succeeds and an invalid one raises
--      a FK violation, which tells an attacker whether a given UUID exists in
--      another tenant without ever reading a row.
--
-- The fix is to make a cross-tenant reference unrepresentable rather than merely
-- forbidden: every tenant-owned parent gets UNIQUE (organization_id, id), and
-- every child references that pair. A child in organization A cannot then point
-- at a parent in organization B, because the pair simply does not exist.
--
-- Found by the isolation suite (the "cannot link its own patient into another
-- clinic's household" case), not by inspection.
-- =============================================================================

-- Composite unique keys on every tenant-owned parent, so a child can
-- reference it only by (organization_id, id) together.
ALTER TABLE app.appointment_types ADD CONSTRAINT appointment_types_org_id_key UNIQUE (organization_id, id);
ALTER TABLE app.appointments ADD CONSTRAINT appointments_org_id_key UNIQUE (organization_id, id);
ALTER TABLE app.automation_rules ADD CONSTRAINT automation_rules_org_id_key UNIQUE (organization_id, id);
ALTER TABLE app.campaigns ADD CONSTRAINT campaigns_org_id_key UNIQUE (organization_id, id);
ALTER TABLE app.doctors ADD CONSTRAINT doctors_org_id_key UNIQUE (organization_id, id);
ALTER TABLE app.domain_events ADD CONSTRAINT domain_events_org_id_key UNIQUE (organization_id, id);
ALTER TABLE app.health_conditions ADD CONSTRAINT health_conditions_org_id_key UNIQUE (organization_id, id);
ALTER TABLE app.households ADD CONSTRAINT households_org_id_key UNIQUE (organization_id, id);
ALTER TABLE app.invoices ADD CONSTRAINT invoices_org_id_key UNIQUE (organization_id, id);
ALTER TABLE app.leads ADD CONSTRAINT leads_org_id_key UNIQUE (organization_id, id);
ALTER TABLE app.patient_timeline_events ADD CONSTRAINT patient_timeline_events_org_id_key UNIQUE (organization_id, id);
ALTER TABLE app.patients ADD CONSTRAINT patients_org_id_key UNIQUE (organization_id, id);
ALTER TABLE app.payments ADD CONSTRAINT payments_org_id_key UNIQUE (organization_id, id);
ALTER TABLE app.prescriptions ADD CONSTRAINT prescriptions_org_id_key UNIQUE (organization_id, id);
ALTER TABLE app.services ADD CONSTRAINT services_org_id_key UNIQUE (organization_id, id);
ALTER TABLE app.websites ADD CONSTRAINT websites_org_id_key UNIQUE (organization_id, id);

-- Re-point every single-column FK at the composite key.
ALTER TABLE app.appointments DROP CONSTRAINT appointments_appointment_type_id_fkey;
ALTER TABLE app.appointments ADD CONSTRAINT appointments_appointment_type_id_fkey
  FOREIGN KEY (organization_id, appointment_type_id) REFERENCES app.appointment_types (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.consultation_notes DROP CONSTRAINT consultation_notes_appointment_id_fkey;
ALTER TABLE app.consultation_notes ADD CONSTRAINT consultation_notes_appointment_id_fkey
  FOREIGN KEY (organization_id, appointment_id) REFERENCES app.appointments (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.followups DROP CONSTRAINT followups_appointment_id_fkey;
ALTER TABLE app.followups ADD CONSTRAINT followups_appointment_id_fkey
  FOREIGN KEY (organization_id, appointment_id) REFERENCES app.appointments (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.invoices DROP CONSTRAINT invoices_appointment_id_fkey;
ALTER TABLE app.invoices ADD CONSTRAINT invoices_appointment_id_fkey
  FOREIGN KEY (organization_id, appointment_id) REFERENCES app.appointments (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.prescriptions DROP CONSTRAINT prescriptions_appointment_id_fkey;
ALTER TABLE app.prescriptions ADD CONSTRAINT prescriptions_appointment_id_fkey
  FOREIGN KEY (organization_id, appointment_id) REFERENCES app.appointments (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.automation_actions DROP CONSTRAINT automation_actions_rule_id_fkey;
ALTER TABLE app.automation_actions ADD CONSTRAINT automation_actions_rule_id_fkey
  FOREIGN KEY (organization_id, rule_id) REFERENCES app.automation_rules (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.automation_runs DROP CONSTRAINT automation_runs_rule_id_fkey;
ALTER TABLE app.automation_runs ADD CONSTRAINT automation_runs_rule_id_fkey
  FOREIGN KEY (organization_id, rule_id) REFERENCES app.automation_rules (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.automation_triggers DROP CONSTRAINT automation_triggers_rule_id_fkey;
ALTER TABLE app.automation_triggers ADD CONSTRAINT automation_triggers_rule_id_fkey
  FOREIGN KEY (organization_id, rule_id) REFERENCES app.automation_rules (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.campaign_recipients DROP CONSTRAINT campaign_recipients_campaign_id_fkey;
ALTER TABLE app.campaign_recipients ADD CONSTRAINT campaign_recipients_campaign_id_fkey
  FOREIGN KEY (organization_id, campaign_id) REFERENCES app.campaigns (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.appointments DROP CONSTRAINT appointments_doctor_id_fkey;
ALTER TABLE app.appointments ADD CONSTRAINT appointments_doctor_id_fkey
  FOREIGN KEY (organization_id, doctor_id) REFERENCES app.doctors (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.consultation_notes DROP CONSTRAINT consultation_notes_doctor_id_fkey;
ALTER TABLE app.consultation_notes ADD CONSTRAINT consultation_notes_doctor_id_fkey
  FOREIGN KEY (organization_id, doctor_id) REFERENCES app.doctors (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.doctor_availability DROP CONSTRAINT doctor_availability_doctor_id_fkey;
ALTER TABLE app.doctor_availability ADD CONSTRAINT doctor_availability_doctor_id_fkey
  FOREIGN KEY (organization_id, doctor_id) REFERENCES app.doctors (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.doctor_clinics DROP CONSTRAINT doctor_clinics_doctor_id_fkey;
ALTER TABLE app.doctor_clinics ADD CONSTRAINT doctor_clinics_doctor_id_fkey
  FOREIGN KEY (organization_id, doctor_id) REFERENCES app.doctors (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.health_conditions DROP CONSTRAINT health_conditions_diagnosed_by_fkey;
ALTER TABLE app.health_conditions ADD CONSTRAINT health_conditions_diagnosed_by_fkey
  FOREIGN KEY (organization_id, diagnosed_by) REFERENCES app.doctors (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.prescriptions DROP CONSTRAINT prescriptions_doctor_id_fkey;
ALTER TABLE app.prescriptions ADD CONSTRAINT prescriptions_doctor_id_fkey
  FOREIGN KEY (organization_id, doctor_id) REFERENCES app.doctors (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.automation_runs DROP CONSTRAINT automation_runs_domain_event_id_fkey;
ALTER TABLE app.automation_runs ADD CONSTRAINT automation_runs_domain_event_id_fkey
  FOREIGN KEY (organization_id, domain_event_id) REFERENCES app.domain_events (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.condition_timeline_events DROP CONSTRAINT condition_timeline_events_health_condition_id_fkey;
ALTER TABLE app.condition_timeline_events ADD CONSTRAINT condition_timeline_events_health_condition_id_fkey
  FOREIGN KEY (organization_id, health_condition_id) REFERENCES app.health_conditions (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.followups DROP CONSTRAINT followups_health_condition_id_fkey;
ALTER TABLE app.followups ADD CONSTRAINT followups_health_condition_id_fkey
  FOREIGN KEY (organization_id, health_condition_id) REFERENCES app.health_conditions (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.family_recurrence_flags DROP CONSTRAINT family_recurrence_flags_household_id_fkey;
ALTER TABLE app.family_recurrence_flags ADD CONSTRAINT family_recurrence_flags_household_id_fkey
  FOREIGN KEY (organization_id, household_id) REFERENCES app.households (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.patient_household_links DROP CONSTRAINT patient_household_links_household_id_fkey;
ALTER TABLE app.patient_household_links ADD CONSTRAINT patient_household_links_household_id_fkey
  FOREIGN KEY (organization_id, household_id) REFERENCES app.households (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.invoice_items DROP CONSTRAINT invoice_items_invoice_id_fkey;
ALTER TABLE app.invoice_items ADD CONSTRAINT invoice_items_invoice_id_fkey
  FOREIGN KEY (organization_id, invoice_id) REFERENCES app.invoices (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.payments DROP CONSTRAINT payments_invoice_id_fkey;
ALTER TABLE app.payments ADD CONSTRAINT payments_invoice_id_fkey
  FOREIGN KEY (organization_id, invoice_id) REFERENCES app.invoices (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.lead_events DROP CONSTRAINT lead_events_lead_id_fkey;
ALTER TABLE app.lead_events ADD CONSTRAINT lead_events_lead_id_fkey
  FOREIGN KEY (organization_id, lead_id) REFERENCES app.leads (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.condition_timeline_events DROP CONSTRAINT condition_timeline_events_timeline_event_id_fkey;
ALTER TABLE app.condition_timeline_events ADD CONSTRAINT condition_timeline_events_timeline_event_id_fkey
  FOREIGN KEY (organization_id, timeline_event_id) REFERENCES app.patient_timeline_events (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.allergies DROP CONSTRAINT allergies_patient_id_fkey;
ALTER TABLE app.allergies ADD CONSTRAINT allergies_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.appointments DROP CONSTRAINT appointments_patient_id_fkey;
ALTER TABLE app.appointments ADD CONSTRAINT appointments_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.campaign_recipients DROP CONSTRAINT campaign_recipients_patient_id_fkey;
ALTER TABLE app.campaign_recipients ADD CONSTRAINT campaign_recipients_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.communication_preferences DROP CONSTRAINT communication_preferences_patient_id_fkey;
ALTER TABLE app.communication_preferences ADD CONSTRAINT communication_preferences_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.consultation_notes DROP CONSTRAINT consultation_notes_patient_id_fkey;
ALTER TABLE app.consultation_notes ADD CONSTRAINT consultation_notes_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.email_messages DROP CONSTRAINT email_messages_patient_id_fkey;
ALTER TABLE app.email_messages ADD CONSTRAINT email_messages_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.followups DROP CONSTRAINT followups_patient_id_fkey;
ALTER TABLE app.followups ADD CONSTRAINT followups_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.health_conditions DROP CONSTRAINT health_conditions_patient_id_fkey;
ALTER TABLE app.health_conditions ADD CONSTRAINT health_conditions_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.households DROP CONSTRAINT households_primary_contact_fk;
ALTER TABLE app.households ADD CONSTRAINT households_primary_contact_fk
  FOREIGN KEY (organization_id, primary_contact_patient_id) REFERENCES app.patients (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.invoices DROP CONSTRAINT invoices_patient_id_fkey;
ALTER TABLE app.invoices ADD CONSTRAINT invoices_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.leads DROP CONSTRAINT leads_patient_id_fkey;
ALTER TABLE app.leads ADD CONSTRAINT leads_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.medical_history DROP CONSTRAINT medical_history_patient_id_fkey;
ALTER TABLE app.medical_history ADD CONSTRAINT medical_history_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.opt_outs DROP CONSTRAINT opt_outs_patient_id_fkey;
ALTER TABLE app.opt_outs ADD CONSTRAINT opt_outs_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.patient_consents DROP CONSTRAINT patient_consents_patient_id_fkey;
ALTER TABLE app.patient_consents ADD CONSTRAINT patient_consents_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.patient_documents DROP CONSTRAINT patient_documents_patient_id_fkey;
ALTER TABLE app.patient_documents ADD CONSTRAINT patient_documents_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.patient_household_links DROP CONSTRAINT patient_household_links_patient_id_fkey;
ALTER TABLE app.patient_household_links ADD CONSTRAINT patient_household_links_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.patient_timeline_events DROP CONSTRAINT patient_timeline_events_patient_id_fkey;
ALTER TABLE app.patient_timeline_events ADD CONSTRAINT patient_timeline_events_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.payments DROP CONSTRAINT payments_patient_id_fkey;
ALTER TABLE app.payments ADD CONSTRAINT payments_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.prescriptions DROP CONSTRAINT prescriptions_patient_id_fkey;
ALTER TABLE app.prescriptions ADD CONSTRAINT prescriptions_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE RESTRICT;
ALTER TABLE app.reviews DROP CONSTRAINT reviews_patient_id_fkey;
ALTER TABLE app.reviews ADD CONSTRAINT reviews_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.sms_messages DROP CONSTRAINT sms_messages_patient_id_fkey;
ALTER TABLE app.sms_messages ADD CONSTRAINT sms_messages_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.whatsapp_messages DROP CONSTRAINT whatsapp_messages_patient_id_fkey;
ALTER TABLE app.whatsapp_messages ADD CONSTRAINT whatsapp_messages_patient_id_fkey
  FOREIGN KEY (organization_id, patient_id) REFERENCES app.patients (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.payment_transactions DROP CONSTRAINT payment_transactions_payment_id_fkey;
ALTER TABLE app.payment_transactions ADD CONSTRAINT payment_transactions_payment_id_fkey
  FOREIGN KEY (organization_id, payment_id) REFERENCES app.payments (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.prescription_items DROP CONSTRAINT prescription_items_prescription_id_fkey;
ALTER TABLE app.prescription_items ADD CONSTRAINT prescription_items_prescription_id_fkey
  FOREIGN KEY (organization_id, prescription_id) REFERENCES app.prescriptions (organization_id, id) ON DELETE CASCADE;
ALTER TABLE app.appointments DROP CONSTRAINT appointments_service_id_fkey;
ALTER TABLE app.appointments ADD CONSTRAINT appointments_service_id_fkey
  FOREIGN KEY (organization_id, service_id) REFERENCES app.services (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.invoice_items DROP CONSTRAINT invoice_items_service_id_fkey;
ALTER TABLE app.invoice_items ADD CONSTRAINT invoice_items_service_id_fkey
  FOREIGN KEY (organization_id, service_id) REFERENCES app.services (organization_id, id) ON DELETE SET NULL;
ALTER TABLE app.website_sections DROP CONSTRAINT website_sections_website_id_fkey;
ALTER TABLE app.website_sections ADD CONSTRAINT website_sections_website_id_fkey
  FOREIGN KEY (organization_id, website_id) REFERENCES app.websites (organization_id, id) ON DELETE CASCADE;
