# Clinic Growth OS

Multi-tenant clinic management and growth platform for the Indian healthcare market.

**The specification is [`docs/MASTER_PROMPT.md`](docs/MASTER_PROMPT.md).** Read it before making an
architectural decision. This README covers only how to run the thing.

Current state: **milestone M0 — scaffold and tenant-isolation spike.**

---

## Requirements

- Node >= 20.11 (developed on 24)
- No database installation needed. The test suite boots a real Postgres from a binary in
  `node_modules`.

## Setup

```bash
npm install
cp .env.example .env.local   # fill in DATABASE_URL only when you have one
```

## Commands

| Command              | What it does                                                 |
| -------------------- | ------------------------------------------------------------ |
| `npm run dev`        | Next.js dev server on :3000                                  |
| `npm run verify`     | typecheck + lint + format + full test suite — the merge gate |
| `npm test`           | All tests, booting Postgres automatically                    |
| `npm run test:rls`   | Tenant-isolation suite only                                  |
| `npm run db:migrate` | Applies `migrations/*.sql` in order, as the **owner** role   |
| `npm run typecheck`  | `tsc --noEmit`                                               |

## The two database roles (§9, §9.1)

This is the part most likely to be got wrong, so it is worth stating plainly.

| Variable                | Role                                  | Used for                          |
| ----------------------- | ------------------------------------- | --------------------------------- |
| `DATABASE_URL`          | `clinic_os_app`                       | Every application request         |
| `DATABASE_URL_UNPOOLED` | owner (`postgres`, or Neon's default) | Migrations and test fixtures only |

**A table's owner bypasses that table's RLS policies.** If the application connects as the owner,
every policy in `migrations/0001_tenancy_spike.sql` silently stops applying and the test suite still
passes. `clinic_os_app` owns nothing, has no `BYPASSRLS`, and cannot run DDL; every tenant table is
additionally set `FORCE ROW LEVEL SECURITY`. Two independent defences, because one is not enough for
the boundary the whole product's security rests on.

## Running the RLS suite

```bash
npm run test:rls
```

By default this boots an ephemeral Postgres (see `tests/global-setup.ts`), applies the migrations as
the owner, grants `clinic_os_app` a local-only password, and runs the isolation tests as that
unprivileged role. Nothing is installed on your machine and nothing persists.

To run against a real Neon branch instead, set both `DATABASE_URL` and `DATABASE_URL_UNPOOLED` and
the embedded server is skipped.

### This suite is mutation-tested

A passing security test proves nothing unless a broken policy would fail it. Five deliberate defects
were introduced and confirmed to be caught:

| Defect introduced                                                    | Caught |
| -------------------------------------------------------------------- | ------ |
| `ENABLE ROW LEVEL SECURITY` without `FORCE`                          | yes    |
| `current_org_ids()` returning every org on empty context (fail-open) | yes    |
| A policy loosened to `USING (true)`                                  | yes    |
| `clinic_os_app` granted `BYPASSRLS`                                  | yes    |
| `set_tenant_context()` ignoring the user id                          | yes    |

One further finding worth recording: removing `WITH CHECK` from a `FOR ALL` policy is **not** caught,
because Postgres reuses the `USING` expression as the check when `WITH CHECK` is omitted. It is
written explicitly regardless — see the comment in the migration.

## How a request reaches tenant data

```
Server Action / Route Handler
  -> verify the Better Auth session server-side          (M2)
  -> withTenant(userId, tx => ...)                        src/lib/db/tenant.ts
       BEGIN
       SELECT app.set_tenant_context($userId)             the database derives
                                                          membership from clinic_users
       ... queries run under RLS ...
       COMMIT
```

The application passes **only a verified user id**. It never passes an organization or clinic id, and
never computes membership. That is deliberate: §8 forbids trusting a client-supplied tenant id, and
the cheapest way to guarantee it is to leave no parameter through which one could be supplied.

Nothing may take a connection from the pool directly. If a query runs outside `withTenant()` it runs
with no context, and because the helpers fail closed it returns nothing rather than leaking — but it
is still a bug.

## Layout

```
migrations/     hand-authored SQL. RLS policies and helper functions live here,
                versioned alongside the tables they protect.
src/config/     environment, validated once at startup
src/lib/db/     connection pool + the tenant bridge
src/lib/providers/  §46 interfaces and mocks — business logic never imports a vendor SDK
tests/rls/      the tenant-isolation suite
```

## What is deliberately not here yet

M0 is the security foundation on a four-table schema. Authentication, the full entity model
including the Family Health Graph, domain resolution, and every product feature come in M1 onward —
see the milestone sequence in the Phase 1 proposal.
