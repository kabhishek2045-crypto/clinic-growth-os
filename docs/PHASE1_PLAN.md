<!-- /autoplan restore point: /Users/anupkumarsinha/.gstack/projects/sddigital-Clinic-OS/main-autoplan-restore-20260826-104139.md -->
# Clinic Growth OS — Phase 1 Delivery Plan (M2–M13)

Derived from the approved §63 architecture proposal. `docs/MASTER_PROMPT.md` remains the
canonical specification (§62.1); this file is the execution plan for the remaining Phase 1
MVP boundary defined in §49, and is the input to `/autoplan`.

Branch: `main` · Base: `main` · Platform: GitHub (`sddigital/Clinic-OS`)

---

## 1. Where the build actually is

**Shipped and green** (CI passing, 39 tests against real Neon and an embedded Postgres):

- **M0 — scaffold + tenant-isolation spike** (`f611747`). Next.js 15 / React 19 / TS strict,
  Tailwind, Drizzle, eight `§46` provider interfaces with mocks, CI. Two database roles
  (`clinic_os_app` owns nothing, no `BYPASSRLS`, no DDL), `FORCE ROW LEVEL SECURITY`
  everywhere, fail-closed context helpers, and `withTenant()` — which passes only a
  server-verified user id, letting the database derive membership from `clinic_users`.
  Mutation-tested: `ENABLE`-without-`FORCE`, fail-open helper, `USING (true)`, `BYPASSRLS`
  on the app role, and `set_tenant_context()` ignoring the user id were each introduced and
  each caught.
- **M1 — full Phase 1 schema** (`292441a`). 75 tables, 99 policies, 159 indexes. Family
  Health Graph included per §7.2. Composite `(organization_id, id)` foreign keys throughout,
  after the suite found that FK validation bypasses RLS and all 51 single-column FKs to
  tenant-owned parents were cross-tenant holes. `EXCLUDE` constraint prevents double
  booking. Per-line tax treatment with `exempt` distinct from 0%.
- **Infrastructure.** Neon `young-fog-22492298`, `aws-ap-southeast-1`, Postgres 17.
  Vercel connected, functions pinned to `bom1`.

**Not built:** authentication, every product surface, every provider implementation.

---

## 2. Constraints this plan inherits

- §52 — one milestone at a time; full check pass and a report after each; wait for approval.
- §53 — never trust a client-supplied tenant id; no frontend-only authorization; no secret
  reaches the browser; never bypass RLS.
- §49 — the MVP boundary. Visual Health Advisor content is explicitly out.
- §62.3 — the acceptance gate is the test suite, not the tool that wrote the code.
- §2 — Phase 2 does not begin until Phase 1 is complete and approved.

---

## 3. Remaining milestones

### M2 — Better Auth, RBAC, clinic switcher
Better Auth (pinned exact) for email/password, sessions, password reset. Its generated
tables reconcile with `clinic_users.user_id`, which currently has no FK. Nine roles and the
permission catalogue seeded in M1 become real checks: `requireClinicRole()`,
`user_has_permission()`. Clinic switcher validates the active clinic against membership
server-side on every request. Platform and clinic administration fully separated (§13).
**Risk:** this is where tenant isolation could quietly regress — `withTenant()` currently
trusts its caller to have verified the session, a contract enforced only by convention.

### M3 — Domain resolution, middleware, branding
`resolveTenantFromHost()` against every case in §10: localhost, wildcard subdomains, Vercel
previews, custom domains, www and trailing-dot normalisation, port stripping, suspended and
unverified and unknown domains. Middleware normalises the host, strips inbound tenant
headers, and rewrites — it does not forward tenant identity. Branding as CSS variables only;
unsafe input rejected. `VercelDomainProvider` + `MockDomainProvider`.

### M4 — Clinic onboarding + application shell
§40 flow through branding, with setup-completion indicator. 30-minute target measured.

### M5 — Patients, households, conditions, timeline
The Family Health Graph write path — where §49's "household linking and condition-tagging"
becomes real rather than schema. Unified timeline (§17) with condition filtering.

### M6 — Appointments + Today's Clinic
Availability, types, holidays, rescheduling, waitlist. The `EXCLUDE` constraint already
exists; this builds the UX and tests it under concurrent submission. §19 daily screen.

### M7 — Prescriptions, documents, storage
R2 behind `StorageProvider`, tenant-scoped paths, signed URLs, file validation, malware-scan
hook. Branded PDFs. Test proves no permanent public URL exists for a private medical file.

### M8 — Billing
Invoices, per-line tax, branded PDFs, Razorpay behind `PaymentProvider`. Server-side
verification; webhook idempotency already enforced by a unique `provider_event_id`.

### M9 — Website studio, public booking, leads
Eleven templates, SEO and metadata, public booking with rate limiting and anti-spam, lead
capture with UTM attribution preserved through to the appointment (§15, §16, §29).

### M10 — Events, communication, follow-ups, automation v1
Transactional outbox drained by a Vercel Cron worker using `FOR UPDATE SKIP LOCKED`.
WhatsApp workflows from §25. Consent and opt-out enforced before every send. Automation runs
idempotent and proven not to double-execute.

### M11 — Dashboard, subscriptions, platform admin
§28 metrics, each with a documented calculation and period comparison, no fabricated
insights. Entitlements and usage counters. Platform console with audited, time-bounded
impersonation.

### M12 — Patient portal
Mobile-first PWA: appointments, prescriptions, invoices, documents, follow-ups.
"My Health, Explained" tab scaffolded empty awaiting Phase 2.

### M13 — Acceptance, hardening, documentation
§48 end-to-end run automated. Security checklist, backup/DR with stated RPO/RTO and a
*tested* restore, cost assumptions, known limitations, deployment docs.

---

## 4. Open decisions — carried forward, still unanswered

Decisions 1–4 were settled at approval (Drizzle; organization as security boundary;
Better Auth core with our own permission tables; patients as a separate principal type).
These are not:

5. **Multi-location in the MVP UI?** Proceeding as: schema supports it, UI ships
   single-location behind a flag. Affects M4 and M6.
6. **WhatsApp — Meta Cloud API direct, or an Indian BSP?** Template approval has real lead
   time; the §25 templates must be submitted before M10 can be tested against anything real.
   Needs deciding by M8.
7. **GST shape.** Clinical services are largely GST-exempt in India while aesthetics, dental,
   and pharmacy are not. M1 already models tax per invoice line with `exempt` distinct from
   a 0% rate. Needs an accountant's confirmation before M8.
8. **ICD-10 depth.** Proceeding as: full code stored nullable, UI driven by a curated
   per-specialty shortlist of 20–40 conditions. Affects M5 and, later, §32.8.
9. **Data residency.** Neon has no India region; the project is in Singapore. Needs an
   Indian data-protection lawyer before the first real patient record. Affects M13.
10. **Prescription legal requirements.** NMC registration number is modelled on `doctors`;
    signature handling and telemedicine guidelines need legal review before M7 ships.
11. **First design-partner clinic's specialty** (§63.4). Decides which of the eleven website
    templates is built properly first and which condition shortlist seeds the taxonomy.
    Defaulting to general physician. Affects M9.
12. **`PLATFORM_ROOT_DOMAIN`.** Still a placeholder. Needed by M3 for subdomain routing.

---

## 5. Known weaknesses in this plan

Stated plainly so the review has something real to attack:

- **Milestone sizing is uneven.** M10 bundles the event system, three communication
  channels, follow-ups, and the automation engine. It is plausibly three milestones.
- **The M2 contract gap.** `withTenant(userId, …)` trusts its caller to have verified the
  session. Nothing enforces that today.
- **No seed script.** §60 wants two fully populated example tenants; they exist only as test
  fixtures.
- **Vercel deploys without waiting for CI.** Branch protection requiring the `verify` check
  is not yet configured, so a commit breaking tenant isolation would still deploy.
- **`embedded-postgres` pulls a 144 MB binary into every Vercel build.** Cached, not fatal,
  but wasteful.
- **No observability.** §43 wants error, latency, and job monitoring. It appears nowhere in
  M2–M13 except implicitly in M13.
- **The 30-minute onboarding target in M4 is asserted, not derived.** Nothing establishes it
  is achievable with the §40 step list.

---

<!-- AUTONOMOUS DECISION LOG -->
# /autoplan Review — Phase 1 (CEO)

Mode: SELECTIVE EXPANSION · Approach B · Voices: Claude subagent only (Codex not installed)

## What already exists (do not rebuild)

| Sub-problem | Shipped in | Consequence for M2-M13 |
|---|---|---|
| Tenant isolation | M0 | M2 must not weaken it |
| Permission catalogue | M1 | M2 wires, does not build |
| Double-booking prevention | M1 (`EXCLUDE`) | M6 is UX only |
| Webhook idempotency | M1 (unique `provider_event_id`) | M8 is wiring |
| Automation idempotency | M1 (unique `idempotency_key`) | M10 is wiring |
| Per-line tax | M1 | M8 is calculation only |
| Provider seams | M0 (8 interfaces + mocks) | M3/M7/M8/M10 implement behind them |

M6, M8 and M10 are thinner than the plan reads.

## NOT in scope (deferred, with reason)

- Staff-side offline mode — outside blast radius, new infra (P2). To TODOS.md.
- Full Phase 1/Phase 2 inversion — §49 forbids; portal, content pipeline and clinician
  review loop do not exist to invert into.
- Speculative indexes — added when the query exists (P3).

## Accepted expansions (now in scope)

1. Family Health Graph as a visible M5 feature — schema built, unused, differentiating.
2. `abha_id` / `abha_linked_at` on `patients` + `AbdmProvider` interface — additive now,
   backfill later.
3. Per-clinic plan seed data (unlimited `doctors`/`staff`) — seed change, not migration.
4. Split M10 into M10a (outbox + worker) and M10b (channels, follow-ups, automation).
5. Observability folded into each milestone, not deferred to M13.
6. Meta-test asserting the harness applied every migration and used the configured database.

## Error & Rescue Registry

| Codepath | Failure | Exception | Rescued | User sees |
|---|---|---|---|---|
| `withTenant()` | pool exhausted | `ConnectionPoolExhausted` | GAP | 500 |
| `set_tenant_context()` | null user id | `invalid_parameter_value` | raises | 500, should be 401 |
| `resolveTenantFromHost()` | unknown host | — | partial | must be 404, never default tenant |
| R2 `signedUrl` (M7) | R2 5xx | `StorageUnavailable` | GAP | broken link |
| Razorpay webhook (M8) | bad signature | `SignatureInvalid` | GAP | silent accept (critical) |
| WhatsApp send (M10) | 429 | `RateLimitError` | GAP | message lost silently |
| Outbox worker (M10a) | poison message | — | GAP | infinite retry |

All six gaps become milestone acceptance criteria. `domain_events.status='dead'` exists and
must be wired.

## Failure Modes Registry

| Mode | Severity | Mitigated? |
|---|---|---|
| Cross-tenant leak via unverified caller of `withTenant` | CRITICAL | NO — convention only |
| Deploy of isolation-breaking commit | CRITICAL | NO — no branch protection |
| Silent webhook / outbox / automation failure | HIGH | NO — no observability until M13 |
| Data residency forces provider migration | HIGH | NO — decision 9 unresolved, Neon coupling real |
| WhatsApp templates rejected after M10 built | MED | NO — decision 6 unresolved |
| Branding stored-XSS via unvalidated jsonb/text | MED | NO — CHECK covers colours only |

## Dream state delta

Moves toward the 12-month ideal on data model. Moves away on positioning: ends at parity
with ~12 incumbents, minus ABDM, with the differentiator unbuilt and unvalidated.

## Decision Audit Trail

| # | Phase | Decision | Class | Principle | Rationale |
|---|-------|----------|-------|-----------|-----------|
| 1 | CEO | Approach B over A/C | Taste | P1,P2 | Cheap differentiator pull-forward; C forbidden by §49 |
| 2 | CEO | Mode = SELECTIVE EXPANSION | Mechanical | default | Iteration on existing system |
| 3 | CEO | Accept expansions 1,2,3,4,6,7 | Taste | P1,P2 | In blast radius, each <1d CC |
| 4 | CEO | Defer offline mode | Mechanical | P2 | Outside blast radius, new infra |
| 5 | §1 | Middleware pinned to Node runtime | Mechanical | P5 | One driver, not two |
| 6 | §1 | Migrations backward-compatible after 0002 | Mechanical | P1 | Rollback posture |
| 7 | §2 | Six rescue gaps become acceptance criteria | Mechanical | P1 | Zero silent failures |
| 8 | §3 | Zod-validate + escape branding text | Mechanical | P1 | Stored-XSS vector |
| 9 | §3 | Magic links 15-min, single-use | Mechanical | P1 | Unspecified |
| 10 | §3 | Rate limit public booking | Mechanical | P1 | §16 requires it |
| 11 | §4 | Idempotency key on booking; cursor pagination; CSRF | Mechanical | P1 | Unhandled edge cases |
| 12 | §5 | `withPlatformAdmin` reason must persist or be deleted | Mechanical | P4 | Parameter that does nothing |
| 13 | §6 | Add concurrency, chaos and host-matrix tests | Mechanical | P1 | Highest-ROI coverage |
| 14 | §7 | One `withTenant()` per request | Mechanical | P5 | 300ms RTT to Singapore |
| 15 | §8 | Sentry + `error_events` in M2 | Taste | P1 | §43; silent-failure systems ship first |
| 16 | §9 | Two-deploy sequence for the Better Auth FK | Mechanical | P1 | Constraining a populated table |
| 17 | §10 | Add `docs/SCHEMA_MAP.md` | Mechanical | P5 | 75 tables, zero screens |
| 18 | §11 | Interaction-state map per UI milestone | Mechanical | P1 | Every cell unspecified |

# /autoplan Review — Phase 2 (Design)

Composite design rating: **1.3/10**. Voices: Claude subagent only (Codex not installed).

CORRECTION: an earlier statement in this review credited M0 with shipping shadcn/ui.
It did not. package.json contains no shadcn, no Radix, no icon set, no font, and
src/components does not exist, despite MASTER_PROMPT §4 mandating shadcn/ui.

| Pass | Score | Core finding |
|---|---|---|
| 1 Information architecture | 2/10 | Today's Clinic lists 8 equal elements, no priority |
| 2 Interaction states | 0/10 | No loading/empty/error/success/partial anywhere |
| 3 User journey | 1/10 | No emotional arc; receptionist and patient arcs unmapped |
| 4 AI slop risk | 3/10 | 11 templates + per-clinic fonts, no design system |
| 5 Design system | 0/10 | No DESIGN.md; shadcn mandated but absent |
| 6 Responsive & a11y | 2/10 | "Mobile-first" for portal only; staff surfaces unaddressed |
| 7 Unresolved decisions | — | 7 logged |

Critical additions from the outside voice: walk-ins have no path; the patient record
leads with a timeline when a doctor needs standing facts first (safety, not taste);
the EXCLUDE constraint has no conflict UX (patient sees a 500); one phone maps to
multiple household members so phone alone is not identity; i18n must be established
in M3; M9 ships a booking that sends the patient nothing because WhatsApp is M10.

# /autoplan Review — Phase 3 (Eng)

| ID | Sev | Conf | Location | Finding |
|---|---|---|---|---|
| E1 | P0 | 9/10 | tenant.ts:39-40 | withTenant takes a raw string; verification is convention |
| E2 | P0 | 10/10 | cross-tenant.test.ts:18 | Tests reimplement withTenant instead of calling it |
| E3 | P1 | 10/10 | package.json | Drizzle declared, zero imports, no drizzle.config.ts |
| E4 | P1 | 9/10 | tenant.ts:76-79 | withPlatformAdmin validates a reason it never persists |
| E5 | P1 | 9/10 | tenant.ts | 4 fixed round trips per call; one is provably redundant |
| E6 | P2 | 9/10 | providers/index.ts:17 | Mocks returned unconditionally, no env seam |
| E7 | P2 | 9/10 | env.ts:31 | BETTER_AUTH_SECRET optional; M2 can ship without it |
| E8 | P2 | 10/10 | package.json:14 | next lint deprecated, removed in Next 16, CI depends on it |
| E9 | P2 | 8/10 | — | No E2E runner installed; §48 acceptance has nothing to run on |

## Phase 3 — verified defects in SHIPPED code (M0/M1)

Found by the eng outside voice, each verified independently before being recorded.

| # | Location | Defect | Why it matters |
|---|---|---|---|
| C1 | `.github/workflows/ci.yml:57` | Greps `.next/static` for secret NAMES | Webpack inlines the VALUE and removes the name. The check cannot detect a leak; it reported "clean" on M0, M1 and the review run. |
| C2 | `src/lib/db/tenant.ts:59` | `clear_tenant_context()` runs after COMMIT | Outside any transaction, `set_config(..., true)` reverts at statement end. It is a no-op; the comment claims it is a second line of defence. |
| C3 | `0002:1305` + `0002:1353` | `error_events` nullable `organization_id` inside `tenant_tables` | `NULL = ANY(...)` is never TRUE, so untenanted errors can never be inserted. Decision 15 (observability in M2) lands on an unwritable table. |
| C4 | `tests/rls/schema.test.ts:247` | Comment says "NOT inside one transaction"; code opens BEGIN and does both INSERTs inside it | Real concurrency makes the second inserter block, not fail. The path M6 will hit is untested. |
| C5 | `0002:1350` | `audit_logs` / `access_logs` get `FOR ALL` | Any org member, including `read_only_staff`, can DELETE their own audit trail. |

## Phase 3 — architectural gap that blocks M3

`app.set_tenant_context()` derives access solely from `clinic_users`. There is no
anonymous, system, or patient principal. Consequences, by milestone:

- **M3** must read `clinic_domains` before authentication -> zero rows -> every host
  resolves as unknown. This blocks the NEXT milestone on line one.
- **M8** unauthenticated Razorpay webhook must write `payment_transactions` -> rejected.
- **M9** public booking must read services/doctors and write leads/appointments -> rejected.
- **M10a** cron outbox worker has no user id at all -> rejected.
- **M12** patients appear in no `clinic_users` row -> a patient session sees nothing.
  `app.current_user_id()` is referenced by no policy.

RESOLVED in migration 0004. Three mutually exclusive principals now exist, each keyed on
its own GUC: staff (`app.current_org_ids`), public (`app.current_public_org_id`) and
patient (`app.current_patient_id`). The separation is the security property — had
`set_public_context` populated `current_org_ids`, every existing `_tenant` policy would
have fired for an anonymous visitor. `app.resolve_domain()` handles the pre-authentication
case and closes the enumeration oracle on `clinic_domains.normalized_domain`. Covered by
25 tests, mutation-verified. M3 is unblocked.

Also required in M2: elevation must become explicit
(`set_tenant_context(p_user_id, p_elevate boolean DEFAULT false)`), `withPlatformAdmin`
must write `audit_logs.impersonation_reason` in the same transaction, and the query seam
must become a tagged template so a raw SQL string is a type error before M2-M13 write
hundreds of queries against `query(text)`.

## Decision Audit Trail (continued)

| # | Phase | Decision | Class | Principle | Rationale |
|---|-------|----------|-------|-----------|-----------|
| 19 | Design | Walk-in quick-add: name + phone only | Mechanical | P1 | Most common Indian clinic event, no path in plan |
| 20 | Design | Patient header band before timeline | Mechanical | P1 | Doctor scrolling a feed for an allergy is a safety issue |
| 21 | Design | Conflict UX for EXCLUDE constraint | Mechanical | P1 | Hardest engineering already done; patient sees a 500 |
| 22 | Design | Phone+OTP identity + household person-picker | Taste | P1 | Reverses Decision 4; one phone maps to five members |
| 23 | Design | i18n boundary established in M3 | Taste | P1 | Retrofit across 12 milestones is the worse option |
| 24 | Design | wa.me deep links from M6 + templates into approval in M5 | Mechanical | P2 | M9 otherwise ships a booking that sends nothing |
| 25 | Design | Split M9 into one template + ten theme presets | Taste | P5 | 11 templates is scope theater |
| 26 | Eng | Design public + patient principals before M2 | Mechanical | P1 | Blocks M3 |
| 27 | Eng | Tagged-template query seam | Mechanical | P5 | Only seam is raw SQL; GUC is forgeable |
| 28 | Eng | Explicit elevation parameter + audit write | Mechanical | P1 | Admin crosses tenants silently on every request |
| 29 | Eng | Fix C1-C5 before M2 | Mechanical | P1 | Three were reported as working and are not |
| 30 | Eng | Composite-FK regression test against pg_constraint | Mechanical | P1 | M1's headline fix can silently reopen |
| 31 | Eng | Suites must call withTenant, not mirror it | Mechanical | P1 | Production path has zero coverage |
| 32 | Eng | Split policies: no UPDATE/DELETE on audit/access/usage logs | Mechanical | P1 | Audited party can rewrite the audit |
| 33 | Eng | `client.release(error)` on the catch path | Mechanical | P1 | Poisoned connection returns to pool |
| 34 | Eng | statement_timeout + idle_in_transaction_session_timeout | Mechanical | P1 | External call inside fn pins a connection |
| 35 | Eng | Connection identity assertion in getPool() | Mechanical | P1 | Whole model rests on one env var |
| 36 | Eng | Invoice sequence table before M8 | Mechanical | P1 | Indian GST requires gapless per-FY numbering |
| 37 | Eng | resolve_domain via SECURITY DEFINER, generic "unavailable" | Mechanical | P1 | Global unique index is a cross-tenant enumeration oracle |
| 38 | Eng | Better Auth spike before M2 scope is fixed | Mechanical | P1 | String ids vs uuid, public vs app schema, needs DDL |
| 39 | Eng | global-setup uses scripts/migrate.ts; CI runs migrate twice | Mechanical | P1 | Re-run and populated-DB paths never tested |
| 40 | Eng | getProviders() throws in production if any slot is a mock | Mechanical | P1 | mockDomain returns verified:true always |

## GSTACK REVIEW REPORT

| Run | Voice | Status | Findings |
|---|---|---|---|
| Phase 1 CEO | Claude subagent | complete | 14 (4 critical, 6 high) |
| Phase 1 CEO | Codex | unavailable | — |
| Phase 2 Design | Claude subagent | complete | 20 (6 critical, 9 high) |
| Phase 2 Design | Codex | unavailable | — |
| Phase 3 Eng | Claude subagent | complete | 19 (3 critical, 9 high) |
| Phase 3 Eng | Codex | unavailable | — |
| Phase 3.5 DX | — | skipped | not a developer-facing product |

Scores: CEO premises 2/6 hold · Design composite 1.3/10 · Eng 2 P0 + 5 verified defects
in shipped code. Cross-model consensus: 0/19 confirmed (Codex not installed); 12
independent agreements across separate voices.

VERDICT: APPROVED WITH REVISIONS (option C-revised). 40 decisions logged. Engineering
fixes and the two low-cost challenges accepted. The public/patient principal model is
required before M2 proceeds. Two strategic challenges remain open by the user's choice.

**UNRESOLVED DECISIONS:**
- UC1: MASTER_PROMPT §49 (defer all visualization) contradicts §50 (the visual layer
  should be the headline, not a Phase 2 footnote). Left open.
- UC2: no design partner exists; whether to gate M4 on signed clinics. Left open.
- Open decisions 5-12 from this plan remain unanswered, of which #9 (data residency)
  gates M5 rather than M13, and #6 (WhatsApp BSP) must start now for template lead time.
