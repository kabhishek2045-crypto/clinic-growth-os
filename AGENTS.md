# Agent Instructions — Clinic Growth OS

Any AI coding agent working in this repository — Claude Code, Antigravity, Cursor, or otherwise — must read **`docs/MASTER_PROMPT.md`** in full before making architectural decisions or writing significant code. That file is the single source of truth for product, architecture, and implementation decisions. Do not diverge from it or improvise around gaps without flagging the gap to the human collaborator first.

## Required discipline for every agent, regardless of tool

- One scoped milestone at a time, followed by the full test pass (TypeScript, lint, unit, integration, migration, RLS, tenant-isolation) before reporting a milestone complete (MASTER_PROMPT.md §52).
- Tenant isolation via Row Level Security (§9) is non-negotiable. Never bypass it, never trust a client-supplied tenant ID, never rely on frontend-only authorization (§53).
- Every change must pass the automated test suite in §47 — especially the cross-tenant-access failure tests — before merge, regardless of which tool generated the change (§62.3). The tool is never the approval; the test suite is.
- Do not begin Phase 2 (§32, Visual Health Advisor) work until the Phase 1 MVP (§49) is approved by the human collaborator.
- Never generate clinically-authoritative anatomy content with a text-to-image model (§32.2, §30). Compose and animate from licensed source art only.

## Start here

Follow **§63 of MASTER_PROMPT.md**. If you are a second collaborator's tool joining this project after Phase 1 has already started, read the current state of `docs/MASTER_PROMPT.md` and the repo's existing code before proposing any change — do not assume you are starting fresh.
