# Clinic Growth OS — Claude Code Instructions

This repository is built from a single source-of-truth specification: **`docs/MASTER_PROMPT.md`**. Read it in full before making any architectural decision or writing significant code. Do not improvise product, schema, or security decisions that this file already answers.

## Core discipline

- **Iterative development (MASTER_PROMPT.md §52):** implement one scoped milestone at a time. After each milestone, run TypeScript checks, lint, unit tests, integration tests, migration validation, RLS tests, and tenant-isolation tests. Then report: files created/modified, database changes, environment variables added, tests added/passed, known issues, and the next recommended step. Wait for approval before continuing.
- **Security-first (§53):** never trust client-provided tenant IDs, never rely on frontend filtering alone, never expose auth secrets or storage credentials to the browser, never bypass Row Level Security. Tenant isolation (§9) is the most important security boundary in this codebase — treat it accordingly.
- **The JWT → Postgres session bridge (§9.1)** is required infrastructure, not optional. Neon + Better Auth does not auto-inject identity into Postgres sessions the way a bundled BaaS would — this must be built and tested explicitly before other tenant-scoped features are built on top of it.
- **Phase discipline (§2, §49):** do not begin Phase 2 (Visual Health Advisor, §32) work until the Phase 1 MVP is complete and approved. The Family Health Graph entities (§6–7: `households`, `patient_household_links`, `health_conditions`) belong in the *first* migration even though their UI ships later.
- **Provider abstractions (§46):** never hard-depend on Neon, Cloudflare R2, or Better Auth directly from business logic — go through the provider interfaces.

## Start here

Follow **§63 of MASTER_PROMPT.md** exactly: inspect the repo, propose architecture and database/entity model, confirm the Phase 1 MVP boundary, flag assumptions and open questions, and wait for approval before large-scale implementation.
