-- =============================================================================
-- 0006_better_auth.sql
--
-- Better Auth's tables, taken into our own migration rather than run by its
-- migrator. Written from the DDL that `getMigrations().compileMigrations()`
-- actually emits for version 1.7.1, with three deliberate changes. A spike
-- verified each of the four collisions empirically before this was written:
--
--   1. Better Auth emits `"id" text primary key` and `"userId" text`. Our
--      clinic_users.user_id is uuid, so the FK was not constructible. Fixed by
--      declaring the columns uuid and configuring
--      advanced.database.generateId to return a uuid. Verified: an end-to-end
--      signUpEmail through the app role produced a valid uuid id and a uuid FK
--      accepted it.
--   2. Its model names are unqualified, so they land in `public`. Verified:
--      public.user, public.session, public.account, public.verification. Fixed
--      by connecting Better Auth with `-c search_path=app`; the spike confirmed
--      zero tables leak into public.
--   3. Its migrator needs DDL. Verified: the app role gets "permission denied
--      for schema public". Fixed by owning the DDL here, under the owner role.
--   4. Its tables ship with rowsecurity=false. Session tokens and password
--      hashes in an unprotected table.
--
-- On (4) the obvious fix — RLS policies for clinic_os_app — does not work, and
-- the spike is why: Better Auth reads `user` by email and `session` by token
-- BEFORE any principal exists, exactly like domain resolution. A policy keyed on
-- a principal would deadlock sign-in.
--
-- So the separation is a ROLE, not a policy. A dedicated clinic_os_auth role
-- reaches these four tables and nothing else; clinic_os_app cannot read them at
-- all. The consequence is worth stating plainly: even total SQL injection in the
-- tenant path cannot read a session token or a password hash, because the role
-- holding those queries has no grant on the tables that store them.
--
-- Note: "user" is a reserved word in Postgres and must be quoted everywhere.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. The auth role
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'clinic_os_auth') THEN
    CREATE ROLE clinic_os_auth NOLOGIN NOINHERIT;
  END IF;
END
$$;

GRANT USAGE ON SCHEMA app TO clinic_os_auth;

-- -----------------------------------------------------------------------------
-- 2. Better Auth's tables, uuid-keyed, in schema app
-- -----------------------------------------------------------------------------
CREATE TABLE app."user" (
  "id"            uuid NOT NULL PRIMARY KEY,
  "name"          text NOT NULL,
  "email"         text NOT NULL UNIQUE,
  "emailVerified" boolean NOT NULL,
  "image"         text,
  "createdAt"     timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"     timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE app."session" (
  "id"        uuid NOT NULL PRIMARY KEY,
  "expiresAt" timestamptz NOT NULL,
  "token"     text NOT NULL UNIQUE,
  "createdAt" timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" timestamptz NOT NULL,
  "ipAddress" text,
  "userAgent" text,
  "userId"    uuid NOT NULL REFERENCES app."user" ("id") ON DELETE CASCADE
);
CREATE INDEX session_user_idx ON app."session" ("userId");
CREATE INDEX session_expires_idx ON app."session" ("expiresAt");

CREATE TABLE app."account" (
  "id"                    uuid NOT NULL PRIMARY KEY,
  "issuer"                text NOT NULL,
  "accountId"             text NOT NULL,
  "providerId"            text NOT NULL,
  "userId"                uuid NOT NULL REFERENCES app."user" ("id") ON DELETE CASCADE,
  "accessToken"           text,
  "refreshToken"          text,
  "idToken"               text,
  "accessTokenExpiresAt"  timestamptz,
  "refreshTokenExpiresAt" timestamptz,
  "scope"                 text,
  "password"              text,
  "createdAt"             timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"             timestamptz NOT NULL
);
CREATE INDEX account_user_idx ON app."account" ("userId");

CREATE TABLE app."verification" (
  "id"         uuid NOT NULL PRIMARY KEY,
  "identifier" text NOT NULL,
  "value"      text NOT NULL,
  "expiresAt"  timestamptz NOT NULL,
  "createdAt"  timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"  timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX verification_identifier_idx ON app."verification" ("identifier");

-- -----------------------------------------------------------------------------
-- 3. Only the auth role may touch them
--
-- RLS is still enabled and forced, so the schema-wide invariant tests continue
-- to hold and a future grant to clinic_os_app would still hit a policy that
-- names only clinic_os_auth. Defence in depth: the grant is the wall, the policy
-- is the second wall.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['user', 'session', 'account', 'verification'] LOOP
    EXECUTE format('ALTER TABLE app.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE app.%I FORCE  ROW LEVEL SECURITY', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON app.%I TO clinic_os_auth', t);
    EXECUTE format(
      'CREATE POLICY %I ON app.%I FOR ALL TO clinic_os_auth USING (true) WITH CHECK (true)',
      t || '_auth_role', t
    );
    -- Explicitly revoke from the tenant role. ALTER DEFAULT PRIVILEGES in 0001
    -- grants DML on new tables in this schema to clinic_os_app, so without this
    -- the crown jewels would be readable by the role that runs tenant queries.
    EXECUTE format('REVOKE ALL ON app.%I FROM clinic_os_app', t);
  END LOOP;
END
$$;

-- -----------------------------------------------------------------------------
-- 4. Close the loop on clinic_users.user_id
--
-- APPLYING THIS TO A POPULATED DATABASE
--
-- These two constraints validate immediately, which is correct here because no
-- production data exists yet. Against a database that already holds membership
-- rows they will fail — as they did on first run against a dev database still
-- holding fixture rows, with:
--
--   insert or update on table "clinic_users" violates foreign key constraint
--
-- That is decision 16's two-deploy sequence arriving on schedule. On a populated
-- database the sequence is: ADD CONSTRAINT ... NOT VALID (enforces on new rows,
-- skips existing ones), backfill app."user" for every distinct user_id already
-- present, then ALTER TABLE ... VALIDATE CONSTRAINT in a second deploy. Do not
-- shortcut it by deleting membership rows.
--
-- It has been an unconstrained uuid since 0001, waiting for this table to exist.
-- The FK is validated with the constraint's own privileges, so clinic_os_app can
-- still insert membership rows without any grant on app."user" -- the same
-- property that made single-column FKs a cross-tenant hole in M1 works in our
-- favour here.
-- -----------------------------------------------------------------------------
ALTER TABLE app.clinic_users
  ADD CONSTRAINT clinic_users_user_fk
  FOREIGN KEY (user_id) REFERENCES app."user" ("id") ON DELETE RESTRICT;

ALTER TABLE app.platform_admins
  ADD CONSTRAINT platform_admins_user_fk
  FOREIGN KEY (user_id) REFERENCES app."user" ("id") ON DELETE RESTRICT;
