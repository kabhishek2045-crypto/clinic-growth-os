# CLINIC GROWTH OS
## "The Personal Health Advisor Platform" — Complete Product, Architecture & Implementation Master Prompt

*This is a single, self-contained specification. It supersedes and merges all prior drafts — there is no separate "v1" or "v2" to cross-reference. Every section below is the current, authoritative instruction.*

---

## 0. ROLE

You are a senior SaaS product architect, staff-level full-stack engineer, security architect, database architect, UX engineer, and AI systems engineer.

Your task is to design and incrementally implement a production-ready, white-label, multi-tenant Clinic Growth OS for the Indian healthcare market.

The product must NOT be treated as a generic CRUD-based clinic management application. It must combine Practice Management, Patient CRM, Clinic Website, Online Appointment Booking, Patient Acquisition, WhatsApp/SMS/Email Communication, Follow-up Management, Billing, Analytics, Workflow Automation, Visual Patient Education, and AI-assisted operations into one cohesive product — and every architecture decision should be evaluated against one additional test: **does this deepen the patient/family's trust in and understanding from this specific clinic, over years?** That test is the difference between this product and any other clinic-CRM on the market, and it is explained in full in Section 1.

Do not optimize for feature count. Optimize for: usability, clinic-owner value, patient comprehension, longitudinal relationship depth, operational efficiency, patient conversion, retention, automation, security, scalability, and SaaS economics — in roughly that order of differentiation value.

---

## 1. PRODUCT THESIS AND POSITIONING

### 1.1 Why this can't just be another clinic CRM
There are many well-built clinic management systems in the Indian market already (Practo Ray, DocEngage, CrelioHealth, Zybra, LiveHealth, Kishan, and others) selling scheduling + WhatsApp reminders + a website + basic CRM. That bundle is now table stakes, not a differentiator. Competing on feature parity with an established, better-funded incumbent is a losing position. Three structural problems with a generic-CRM approach:

1. **The value prop is operational, not relational.** It describes software *for the clinic*. It says nothing about why a *patient* would want their clinic to have it.
2. **"Growth" as pure funnel mechanics** (UTM tracking, campaigns, reactivation blasts) treats the patient as a lead to be converted, not a relationship to be deepened.
3. **There is no reason for a patient to prefer this clinic over the next one**, other than reminders arriving on WhatsApp — which is now a baseline expectation, not a differentiator.

### 1.2 The thesis
> A local clinic's real competitive advantage is trust and continuity — not funnels. Corporate hospital chains and telemedicine apps can out-market and out-fund any single clinic. What they cannot easily replicate is a doctor who *knows this specific patient's family, history, and context* and can *make them understand* their own health.
>
> Clinic Growth OS's job is to turn every local clinic doctor into that patient's **Personal Health Advisor** — not just a transactional visit, but the trusted, ongoing relationship a family keeps coming back to for years.

**Commercial proposition:** *Your clinic runs on it. Your patients trust it. Your doctor becomes irreplaceable.*

This reframing changes what "Growth" and "AI" mean in the product:
- Growth = deepening relationship depth and repeat-visit frequency per family, not just top-of-funnel lead volume.
- AI = helping the doctor *communicate and educate*, not just automate admin tasks.
- The moat = accumulated longitudinal understanding of a patient/family that is expensive for a competitor to replicate, and progressively harder for the patient to walk away from.

### 1.3 The wedge — why this wins against existing clinic software

| Existing clinic CRMs | Clinic Growth OS |
|---|---|
| Treats patient as a "lead" to convert | Treats patient (and family) as a longitudinal relationship to grow |
| Growth = campaigns, reminders, reviews | Growth = comprehension, trust, repeat visits, genuine referral advocacy |
| "AI" = drafting messages, summarizing notes | "AI" = helping the doctor *explain* — the actual bottleneck in Indian OPD care |
| Differentiation = UI polish, WhatsApp automation | Differentiation = a category no competitor owns: visual health education infrastructure |
| Patient experience ends at the invoice | Patient experience continues: they leave understanding *why*, not just *what* |

The single most under-served problem in Indian outpatient care is **time-constrained explanation**: a doctor has 4–7 minutes per patient and no good way to show — rather than tell — what's happening inside the body, why a treatment is needed, or what to expect. This is where the Visual Health Advisor Layer (Section 32) becomes the real differentiator, not a bolt-on feature.

### 1.4 Product pillars (RUN / GROW / AUTOMATE)

**RUN** — Help the clinic operate: Patients, Doctors, Staff, Appointments, Calendar, Prescriptions, Medical documents, Billing, Payments, Reports.

**GROW** — Help the clinic acquire and retain patients — and deepen the relationship, not just fill the funnel: Clinic website, Online booking, Lead capture, Patient CRM, Family Health Graph, Source attribution, WhatsApp, Follow-ups, Review requests, Patient reactivation, Visual patient education, Conversion analytics.

**AUTOMATE** — Reduce repetitive administrative work: Appointment reminders, Follow-up reminders, No-show workflows, Lead assignment, Patient reactivation, Communication workflows, AI-assisted tasks, Clinic performance summaries.

---

## 2. TWO-PHASE PRODUCT VISION

**Phase 1 — Clinic Management OS (the foundation).** Everything a clinic needs to run cleanly and be digitally competent: patients, appointments, prescriptions, billing, staff, a real clinic website, WhatsApp communication, and clean multi-tenant SaaS infrastructure — detailed in full in Sections 3–31 and 33–48 below. Necessary but not sufficient: this is the plumbing that earns the right to sell Phase 2.

**Phase 1.5 — The Family Health Graph (bridge).** Before you can *visualize* a condition, you need a longitudinal, structured, patient-and-family-linked health record — not just a stack of prescription PDFs. This is the connective tissue between Phase 1 and Phase 2, and it must be built into the schema from day one (Section 7.2), not deferred. Deferring it means an expensive backfill later.

**Phase 2 — Visual Health Advisor Layer ("Explain My Health").** Interactive 2D animated anatomy and condition visualization the doctor uses live in the consultation room to explain diagnosis, procedure, and treatment, which the patient can then revisit on the patient portal in their own language. This is the category-defining feature. Fully specified in Section 32.

**Phase 3 — AI Health Copilot & Predictive Care.** The full Clinic Copilot (Section 31) plus proactive health guidance: AI notices patterns across a family's longitudinal record (an overdue diabetic follow-up, a missed vaccination, a recurring complaint pattern) and prompts the clinic to reach out — turning the clinic from reactive to proactive, which is the actual definition of "personal health advisor." AI never diagnoses or prescribes autonomously — this constraint (Section 30) is non-negotiable.

**Roadmap sequencing:**
- **Months 1–4 (Phase 1 MVP):** Full Clinic Management OS per Sections 3–48, with the Family Health Graph data layer (Section 7.2) built in from the start migration.
- **Months 4–5 (Phase 1.5):** Patient portal, first cut of the automation engine, source-attribution maturity — validate retention and repeat-visit metrics before investing in Phase 2 content.
- **Months 5–9 (Phase 2):** Build the SVG/GSAP rendering + Fabric.js annotation layer once (Section 32), then run the Specialty Content Onboarding Workflow (Section 32.8) as part of every clinic's standard white-label onboarding conversation, starting wherever your first customer's specialty happens to be. Instrument adoption and consultation-time impact before assuming demand in other specialties. No 3D licensing or 3D build in this phase.
- **Months 9+ (Phase 3):** Clinic Copilot, proactive health-graph-driven outreach, review management, patient reactivation, advanced analytics, ABDM/enterprise integrations, API platform.

---

## 3. PRIMARY USERS

- **Clinic Owner** — revenue, patient growth, conversion, retention, staff management, collections, business insights, and — as newly tracked outcomes — *family retention rate* and *patient comprehension/satisfaction*.
- **Doctor** — today's appointments, patient history, consultation workflow, prescriptions, follow-ups, and a fast in-consultation visual explanation tool that costs zero extra time (Section 32.5).
- **Receptionist/Staff** — enquiries, appointments, patient registration, waiting queue, reminders, payments, follow-ups.
- **Patient** — clinic information, appointment booking, confirmations, reminders, prescriptions, invoices, documents, follow-ups, communication, and a personal, revisitable, plain-language record of what their doctor explained and why (Section 23.1).
- **Family Unit** (non-login concept) — a household grouping (parents, children, elders) that the clinic and CRM reason about together. Many Indian clinic relationships are family relationships, not individual-patient relationships; the data model and CRM logic reflect this (Section 7.2).

The UI must not expose unnecessary complexity to users who do not need it. Receptionist workflow: speed. Doctor workflow: minimal administrative burden. Owner workflow: business outcomes. Patient workflow: minimal friction.

---

## 4. TECHNOLOGY STACK

Use Next.js App Router, TypeScript, Neon (serverless PostgreSQL), Cloudflare R2 (object storage), Better Auth (self-hosted authentication), Vercel, Tailwind CSS, shadcn/ui, Zod, Server Components by default, Server Actions where appropriate, and Route Handlers where appropriate.

Use strict TypeScript. Never use `any` unless absolutely unavoidable and explicitly justified.

Use one codebase and one deployment initially. Optimize for the first 100+ paying clinics without requiring a fundamental rewrite. Do not prematurely introduce Kubernetes, microservices, separate databases per clinic, Kafka, or heavyweight infrastructure unless actual scale requires it.

### 4.1 Database — Neon (PostgreSQL)
Mature, GA, Databricks-backed. Use branching for per-PR/per-feature preview environments and for cheap, isolated dev/staging copies of the schema. Scale-to-zero keeps development cost at $0 while idle. `pgvector` is included at no extra cost — reserve this for the Phase 3 Clinic Copilot (embeddings for AI-assisted retrieval) rather than provisioning a separate vector store later.

### 4.2 Storage — Cloudflare R2
S3-compatible, GA, mature. Implement behind the `StorageProvider` abstraction (Section 43) — never call R2's API directly from business logic. Private buckets for medical documents, prescriptions, and invoices; public bucket only for logos and public doctor images. R2's zero-egress-fee model is a structural cost advantage here specifically because patients repeatedly re-downloading prescriptions/invoices from the portal is an egress-heavy usage pattern that would cost real money on egress-billed providers over time. Full storage requirements in Section 37.

### 4.3 Authentication — Better Auth (self-hosted, MIT license)
Runs inside the Next.js app; no per-MAU bill, ever. The core is stable and production-used; stick to well-trodden features (email/password, sessions, RBAC/organizations plugin) rather than newer or niche plugins early on. Pin the version and review release notes before upgrading — as an actively-developed project it does ship occasional breaking changes between minor versions, which is a normal maintenance cost to budget for, not a stability red flag.

**The critical architectural consequence of not using a bundled BaaS:** a platform like Supabase auto-injects a verified user's JWT claims into every Postgres session, which is what lets RLS policies simply check `auth.uid()`. Neon + Better Auth does not do this automatically — it must be built explicitly. This is specified in full in Section 9, and it is the single most important piece of security engineering in this project: it is the tenant-isolation boundary the entire product's security model depends on.

### 4.4 Migration portability
If a future move to a bundled BaaS (Supabase or otherwise) is ever warranted — e.g., a genuine need for a bundled realtime layer, or a preference for less infrastructure to operate once cost is no longer the constraint — the cost should be contained by design, not a rewrite: database migration is a standard Postgres-to-Postgres move; storage migration is a new `StorageProvider` implementation plus a bulk copy; auth migration is the one real effort (user re-authentication at cutover, and rewriting the inside of the centralized permission helper functions from Section 9), made materially easier by keeping that logic centralized rather than scattered across the codebase.

---

## 5. MULTI-TENANT ARCHITECTURE

Use a shared multi-tenant architecture. Do NOT create a separate database instance or deployment for every clinic.

Conceptual hierarchy: Organization → Locations/Clinics → Users, Doctors, Services, Subscription.

A patient may belong to an organization while appointments may belong to a particular location. Design the schema so multi-location clinics can be introduced without redesigning the entire database.

```
One Vercel deployment
+-- Platform
+-- Tenant A
+-- Tenant B
+-- Tenant C
```

---

## 6. CORE DATA MODEL

**SaaS entities:** organizations, clinics/locations, clinic_domains, clinic_branding, clinic_settings, clinic_users, user_profiles, subscriptions, plans, features, plan_features, entitlements, usage_events, usage_counters, feature_flags

**Clinical entities:** doctors, staff, patients, patient_consents, patient_documents, medical_history, allergies, appointments, appointment_types, doctor_availability, prescriptions, prescription_items, consultation_notes

**Commercial entities:** invoices, invoice_items, payments, payment_transactions, taxes, discounts

**Growth entities:** leads, lead_sources, lead_events, patient_timeline_events, campaigns, campaign_recipients, followups, reviews, referral_sources

**Communication entities:** whatsapp_messages, sms_messages, email_messages, communication_templates, communication_preferences, opt_outs

**Automation entities:** automation_rules, automation_triggers, automation_actions, automation_runs

**Platform entities:** audit_logs, access_logs, system_events, integration_connections, webhooks, error_events

**Family Health Graph entities (new — required before Phase 2, built into the first migration):**
- `households` — id, clinic_id, primary_contact_patient_id, address, created_at
- `patient_household_links` — patient_id, household_id, relationship (self, spouse, child, parent, dependent)
- `health_conditions` — id, patient_id, condition_code (ICD-10 where feasible), status (active, resolved, chronic, monitoring), diagnosed_at, diagnosed_by
- `condition_timeline_events` — links `patient_timeline_events` to a specific `health_condition_id`, enabling "show me everything related to this patient's diabetes" rather than just a flat chronological feed
- `family_recurrence_flags` — system-generated signals like "3 members of this household have visited for respiratory complaints in 30 days," computed, never fabricated (same rule as Section 28)

This layer does not replace the clinical entities above — it extends them with relationship and condition-level structure. RLS and tenant-isolation rules (Sections 8–9) apply to it unchanged — a household is a grouping construct, never a security boundary.

**Visual Health Advisor entities (see full context in Section 32):**
- `anatomy_content_items` — id, specialty, condition_code, title (represents the *condition*, not a specific graphic — a condition can have multiple approved variants underneath)
- `anatomy_content_variants` — id, content_item_id, variant_label (internal note only, never a doctor's name), content_type, language_variants[], asset_ref, license_source, status (pending_review | approved | rejected | archived), reviewed_by (internal audit only, never surfaced in UI), reviewed_at, created_at, usage_count, last_used_at
- `doctor_content_preferences` — doctor_id, content_item_id, preferred_variant_id, updated_at
- `education_sessions` — id, clinic_id, patient_id, doctor_id, appointment_id, content_item_id, variant_id, doctor_annotations (structured coordinates + notes), delivered_language, created_at
- `patient_education_history` — denormalized view over `education_sessions`, surfaced on the patient portal and patient timeline
- `condition_content_map` — maps `health_conditions.condition_code` → `content_item_id`
- `content_requests` — id, clinic_id (nullable — null means "shared specialty library"), specialty, requested_conditions[], status (intake | coverage_audit | composing | pending_review | approved), requested_by, created_at

Use UUID primary keys, foreign keys, appropriate indexes, and consistent timestamps. Use soft deletion where appropriate. Do not physically delete sensitive clinical records simply because a UI user clicked Delete unless policy explicitly permits it.

---

## 7. THE FAMILY HEALTH GRAPH — WHY AND HOW

### 7.1 Why
v1-style flat, patient-scoped models (`patients`, `medical_history`, `patient_timeline_events`) are fine for billing but insufficient for the personal-health-advisor thesis, where the actual unit of trust is often the *household*. Building this layer in from day one avoids a costly schema migration and data backfill once Phase 2 needs structured, condition-tagged, family-linked data to attach visuals to.

### 7.2 What's required in the Phase 1 MVP
The full entity list is in Section 6. Do not defer `households`, `patient_household_links`, and `health_conditions` to Phase 2 — they must be in the first migration, even though the UI/automation built on top of them ships later. This is the single most important "don't do this later, do it now" instruction in this document.

---

## 8. TENANT SECURITY

Tenant isolation is a critical security boundary.

Never identify a tenant only from query parameters, hidden form fields, submitted clinic_id, URL parameters, client-side state, or localStorage.

Resolve tenant context from authenticated user membership, verified request hostname, server-side tenant/domain lookup, and authorization checks:

```
resolveTenantFromHost()
getCurrentTenant()
requireCurrentTenant()
getCurrentClinicUser()
requireClinicRole()
requirePlatformAdmin()
assertTenantAccess()
```

These functions must not be spoofable through request parameters.

---

## 9. DATABASE SECURITY AND ROW LEVEL SECURITY

Enable PostgreSQL Row Level Security on every tenant-owned table.

Create secure helper functions where appropriate: `current_user_organization_ids()`, `current_user_clinic_ids()`, `user_has_clinic_role()`, `user_has_permission()`, `is_platform_admin()`.

SECURITY DEFINER functions must use a fixed search_path, minimize privileges, avoid unsafe dynamic SQL, and be independently tested.

A clinic user must never access another clinic's patients, prescriptions, invoices, documents, staff, appointments, messages, or audit records. Platform administrators may access multiple tenants only through explicit privileged authorization. Automated tests MUST attempt cross-tenant access and prove that it fails (Section 47).

### 9.1 The JWT → Postgres session bridge (required because there is no bundled BaaS)
Because Neon + Better Auth does not automatically inject verified identity into the Postgres session the way a bundled BaaS does, this bridge must be built explicitly:

1. Verify the Better Auth session/JWT server-side inside the Next.js server action or route handler — never trust a client-supplied identity.
2. Open a database transaction (Neon's serverless driver supports transactions) and run `SET LOCAL app.current_user_id = '...'` and `SET LOCAL app.current_clinic_ids = '...'` before executing any tenant-scoped query.
3. Write the SECURITY DEFINER helper functions listed above against `current_setting('app.current_clinic_ids', true)` rather than any framework-specific auth helper. Because these checks are centralized in helper functions rather than repeated inline across every RLS policy, a future migration to a different auth provider only requires rewriting the inside of these functions, not every policy in the schema.
4. Treat this bridge as its own early spike, proven out and tested (including the cross-tenant-access failure tests from Section 47) before the rest of the schema is built on top of it. This is the one piece of the architecture that a bundled BaaS would have given for free — it is the tenant-isolation boundary the entire product's security model depends on, and it belongs in the very first implementation milestone (Section 64).

---

## 10. DOMAIN AND TENANT RESOLUTION

Support `app.example.com`, `clinic-a.example.com`, `clinic-b.example.com`, `abcclinic.com`, and `www.abcclinic.com`.

Create `resolveTenantFromHost(hostname: string)`. Support localhost, development, production, wildcard subdomains, Vercel preview deployments, custom domains, www normalization, port removal, lowercase normalization, trailing-dot normalization, suspended domains, unverified domains, and unknown domains. Never trust arbitrary Host headers without validation.

Domain status: pending, verification_required, verified, active, suspended, removed.

`clinic_domains` fields: id, clinic_id, domain, normalized_domain, domain_type, verification_token, verified_at, status, is_primary, created_at, updated_at. Add a unique index on `normalized_domain`.

---

## 11. NEXT.JS REQUEST ROUTING

Use Next.js Proxy/Middleware appropriately to inspect hostname, resolve tenant, establish tenant context, rewrite internally where necessary, preserve browser URL, exclude static assets and Next.js internals, and prevent tenant switching through URL manipulation.

Invalid domains should receive a safe not-found or suspended response. Do not expose internal tenant IDs unnecessarily in public URLs.

---

## 12. AUTHENTICATION

Use Better Auth (Section 4.3). Support email/password, password reset, session refresh, logout, optional magic link, MFA-ready architecture, and clinic-specific branding on authentication pages.

A user may belong to multiple clinics. Implement a secure clinic switcher. The active clinic must always be validated server-side. Do not rely on frontend route hiding for authorization.

---

## 13. ROLE AND PERMISSION SYSTEM

Initial roles: platform_owner, platform_admin, clinic_owner, clinic_admin, doctor, receptionist, accountant, nurse, read_only_staff.

Use permission-based authorization rather than scattering role-name checks throughout the application. Example permissions: `patients.read/create/update/delete`; `appointments.read/create/update/cancel`; `prescriptions.create/read`; `billing.read/create/refund`; `staff.manage`; `branding.manage`; `domain.manage`; `analytics.read`; `campaigns.manage`; `automation.manage`.

Platform administration and clinic administration must be completely separated.

---

## 14. WHITE-LABEL BRANDING

Each clinic must experience the platform as its own product.

Branding fields: clinic name, logo, favicon, primary color, secondary color, accent color, font, login background, email logo, prescription header, invoice header, footer, support phone, support email, social links, and safe CSS variables.

Never permit arbitrary JavaScript injection or unsafe CSS. Use CSS variables `--clinic-primary`, `--clinic-secondary`, `--clinic-accent`.

Branding must affect page metadata, title, favicon, Open Graph metadata, login, dashboard, website, booking pages, prescription PDFs, invoice PDFs, patient portal, and emails.

**The white-label onboarding conversation is also where the Visual Health Advisor content discussion happens** — see Section 32.8. This is not a separate meeting; it's a standard sub-step of the branding/customization conversation every clinic already goes through.

---

## 15. CLINIC WEBSITE STUDIO

The website should be a first-class product feature. A clinic should be able to create a branded website without technical knowledge.

Initial templates: Dental, Dermatology, Orthopaedic, Paediatric, Gynaecology, Physiotherapy, Ayurveda, General Physician, Psychology, Fertility, Aesthetic.

Website sections: hero, about, doctors, services, treatments, testimonials, FAQs, gallery, contact, location, timings, WhatsApp, and book appointment.

Support SEO title, SEO description, Open Graph image, structured metadata, sitemap, robots, and canonical URLs.

The onboarding flow should be capable of producing a basic clinic website from structured clinic information.

---

## 16. PUBLIC PATIENT ACQUISITION

Treat acquisition as a core product capability. Public pages: `/`, `/about`, `/doctors`, `/services`, `/contact`, `/book-appointment`, `/success`.

Support click-to-call, click-to-WhatsApp, online booking, enquiry capture, consent, UTM tracking, source attribution, campaign attribution, Google referral tracking, anti-spam, rate limiting, and server-side validation.

```
visitor -> lead -> contacted -> qualified -> appointment_booked -> confirmed -> attended -> follow_up -> repeat_visit
```

Never guarantee patient acquisition or revenue.

---

## 17. PATIENT CRM

Patient CRM is a core differentiator, now built on top of the Family Health Graph (Sections 6–7). Create a patient timeline.

Events may include: `website_visit`, `lead_created`, `whatsapp_enquiry`, `phone_call`, `appointment_booked`, `appointment_confirmed`, `appointment_cancelled`, `appointment_completed`, `prescription_created`, `invoice_created`, `payment_received`, `followup_created`, `followup_completed`, `review_requested`, `repeat_visit`, and — new — `education_session_delivered` (Section 32.3).

A patient profile should provide a unified timeline rather than forcing staff to navigate disconnected screens. Distinguish lead, prospect, patient, active patient, inactive patient, and reactivation candidate.

Timeline events can be linked to a specific `health_condition_id` via `condition_timeline_events`, so staff can view "everything related to this patient's diabetes" rather than only a flat chronological feed.

---

## 18. APPOINTMENT SYSTEM

Support calendar, doctor availability, appointment types, working hours, breaks, holidays, booking status, confirmed, cancelled, completed, no-show, rescheduling, waitlist, public booking, and internal booking.

Implement conflict detection server-side. Prevent double booking under concurrent submissions using database-level protection where appropriate.

---

## 19. TODAY'S CLINIC EXPERIENCE

Provide a simplified daily operating screen showing today's appointments, current patient, waiting patients, next patient, walk-ins, follow-ups, and no-shows, with fast access to outstanding payments.

Optimize for receptionists and doctors. The daily workflow should require minimal navigation.

---

## 20. PATIENT MANAGEMENT

Support patient registration, search, profile, contact information, medical history, allergies, documents, consent, appointment history, prescriptions, invoices, payments, follow-ups, communication history, and audit history.

Search may support name, phone, and patient ID. Do not expose sensitive information through insecure search endpoints.

---

## 21. PRESCRIPTIONS

Support doctor-created prescriptions, medicine lines, dosage, frequency, duration, instructions, notes, branded PDF, secure patient access, and audit trail.

Prescription access must be authenticated or provided through secure, expiring access mechanisms. Do not expose permanent public prescription URLs.

---

## 22. BILLING

Support invoices, invoice items, discounts, GST configuration, payment status, payment history, refunds where appropriate, and branded invoice PDFs.

Integrate Razorpay through a provider abstraction. Never trust payment status supplied only by the browser. Use server-side verification and webhook handling.

---

## 23. PATIENT PORTAL

Provide a mobile-first web/PWA patient portal. Patients should be able to access appointments, prescriptions, invoices, documents, follow-ups, clinic communication, and booking. Do not require a native mobile application for MVP. Prefer secure magic-link or authenticated access where appropriate.

### 23.1 "My Health, Explained" (Phase 2)
Once the Visual Health Advisor Layer (Section 32) exists, the portal gains this tab: every visualization shown to the patient or a family member, in the language they picked, revisitable anytime, shareable with family. This is the retention mechanic — patients don't switch clinics easily once their explained-health history lives there, and it's a genuinely useful reason to open the app that isn't "here's your invoice." Since the portal is already a PWA, cache the last few sessions offline via service worker so patients can revisit without a reliable connection.

---

## 24. COMMUNICATION PLATFORM

Create provider interfaces: `WhatsAppProvider`, `SMSProvider`, `EmailProvider`, `PaymentProvider`.

Every outbound message should track clinic_id, patient_id, channel, template, provider_message_id, status, error, sent_at, delivered_at, and read_at.

Support consent, opt-out, rate limits, communication preferences, message templates, and audit logging.

---

## 25. WHATSAPP WORKFLOW ENGINE

Treat WhatsApp as a workflow channel, not merely an API integration.

- Appointment workflow: booked → confirmation → 24-hour reminder → 2-hour reminder.
- No-show workflow: no-show → reschedule message.
- Follow-up workflow: consultation completed → follow-up date → reminder → booking CTA.
- Reactivation workflow: inactive patient → eligibility check → campaign → WhatsApp → booking.

---

## 26. EVENT-DRIVEN ARCHITECTURE

Introduce domain events such as `patient.created`, `patient.updated`, `lead.created`, `lead.contacted`, `lead.qualified`, `appointment.created`, `appointment.confirmed`, `appointment.cancelled`, `appointment.completed`, `appointment.no_show`, `prescription.created`, `invoice.created`, `invoice.paid`, `message.sent`, `message.delivered`, `followup.created`, `followup.completed`.

Events may trigger automation, notifications, analytics, AI processing, audit logs, and communication workflows. Do not make every operation synchronously execute every downstream side effect. Use asynchronous processing where appropriate. The initial implementation may use a lightweight job mechanism, but the architecture must allow migration to a dedicated queue later.

---

## 27. AUTOMATION ENGINE

Create `automation_rules`, `automation_triggers`, `automation_actions`, `automation_runs`, and `automation_templates`.

Support workflows such as: `appointment.confirmed` → send WhatsApp confirmation; `appointment.no_show` → create follow-up task; patient becomes inactive → add to reactivation campaign; payment becomes overdue → notify clinic staff.

Automation execution must be idempotent, auditable, retryable, rate limited, and tenant scoped.

---

## 28. CLINIC GROWTH DASHBOARD

The owner dashboard must focus on business outcomes: new enquiries, appointments booked, confirmed appointments, completed appointments, no-shows, new patients, repeat patients, revenue, conversion rate, source/channel, and follow-ups due.

Compare current period with previous period. Provide actionable, data-backed insights such as uncontacted enquiries, increased no-show rate, top acquisition source, and patients due for follow-up.

Never fabricate insights. Every metric must have a defined calculation.

---

## 29. MARKETING ATTRIBUTION

Capture UTM source, UTM medium, UTM campaign, UTM content, referrer, landing page, campaign source, Google referral, and Meta campaign where available.

Track visitor → lead → appointment → confirmed → attended → revenue.

Report enquiries, bookings, confirmed appointments, attended appointments, cancellations, no-shows, conversion rate, source, campaign, cost per booked appointment, and cost per attended appointment.

Do not claim causality where data only establishes attribution.

---

## 30. AI LAYER

AI must be an assistive and administrative layer.

Initial capabilities may include patient-history summarization, consultation-note assistance, follow-up message drafting, website copy generation, FAQ generation, service description generation, clinic performance summaries, overdue follow-up identification, and administrative task suggestions.

**AI must NOT autonomously diagnose patients, prescribe medication, or make clinical decisions** unless a future feature is specifically designed, validated, reviewed, and legally cleared. This constraint applies without exception to the Visual Health Advisor Layer (Section 32) as well: AI/code may compose and animate real, licensed anatomical source art; it must never *invent* anatomy or generate clinically-authoritative content from a text prompt.

---

## 31. CLINIC COPILOT

Design an extensible AI assistant that can answer questions such as: How did the clinic perform this month? Which patients need follow-up? How many enquiries came from Google? Why did appointments drop last week? Show me patients who haven't returned in six months.

The Copilot must respect tenant boundaries, user permissions, patient privacy, and audit requirements. AI must only retrieve data the requesting user is authorized to access. This is a Phase 3 feature (Section 2) — do not build it before the Family Health Graph (Section 7) and core clinic data are mature enough to give it something meaningful to reason over.

---

## 32. VISUAL HEALTH ADVISOR LAYER — "EXPLAIN MY HEALTH" (PHASE 2)

### 32.1 Product shape
A doctor, mid-consultation, taps a condition (e.g., "Allergic Rhinitis," "Otitis Media," "Type 2 Diabetes") and the system shows an interactive, labeled, animated visualization with plain-language annotations the doctor can point at, mark up, and optionally narrate. At the end of the consultation, that exact explanation — including any doctor annotations — is pushed to the patient portal in the patient's chosen language, so the patient (and their family, if they have portal access) can revisit it at home.

This is not a generic anatomy app. The value is that it is:
1. **Tied to the actual diagnosis on this patient's record** (pulled from `health_conditions`/the prescription), not a generic library the doctor has to search.
2. **Reusable as patient-education content afterward**, closing the loop between "what the doctor said in 5 minutes" and "what the patient actually remembers."
3. **A specialty-templated library**, built one specialty at a time as real clinics come on board (Section 32.8), not an attempt to cover all of human anatomy on day one.

### 32.2 Content and rendering strategy — open-source only, no licensing spend
Do not license a 3D anatomy engine (e.g., BioDigital Human, Complete Anatomy, Visible Body) and do not build a proprietary 3D engine. The product does not need photorealistic 3D to deliver the comprehension win — interactive, well-composed 2D vector animation is sufficient and dramatically cheaper to build and own.

- **Rendering:** SVG + **GSAP** (free, including all plugins, commercial use covered) for interactive anatomy visuals: tap-to-highlight regions, layer peel, morph between healthy/diseased states, animate a process. Use `@gsap/react` for clean lifecycle integration into the Next.js app.
- **Annotation layer:** **Fabric.js** (MIT license) canvas overlay for doctor freehand marks/tap-to-mark during consultation, captured as structured coordinates, not baked into a flattened image.
- **Source art:** licensed, reusable, at no cost. Primary source is **Servier Medical Art (SMART)** — thousands of professional medical illustrations, CC BY 4.0 (free, commercial use, adapt/remix allowed, attribution only), organized into specialty kits including a dedicated ENT kit, plus Respiratory, Neurology, Lymphatic, and Digestive kits that cover adjacent structures. Supplement with **Health Icons** and **Open Science Art** (both CC0, no attribution required) for supporting icons.
- Never generate clinically-authoritative anatomy art with a text-to-image model — generative image tools can produce anatomically incorrect output that looks convincing, which is an unacceptable risk for patient-facing medical content. AI/code may compose and animate real licensed source art; it must not invent anatomy.
- Every visualization must carry a "for patient education, not diagnostic" disclaimer, consistent with the AI-assistive-only boundary in Section 30. Never claim medical accuracy beyond what a licensed clinician has actually verified (Section 32.8).
- If future ambition genuinely requires 3D, the zero-cost path is **React Three Fiber** (Three.js, MIT) with free/CC-licensed model sources (BodyParts3D — CC BY-SA; Z-Anatomy — open-source). Do not build this speculatively; only pursue it once usage data on the 2D layer shows a specific comprehension gap 2D can't close.

### 32.3 Data model
See Section 6 for the full `anatomy_content_items` / `anatomy_content_variants` / `doctor_content_preferences` / `education_sessions` / `patient_education_history` / `condition_content_map` / `content_requests` schema.

**Variant selection rule (protects the in-consultation UX constraint in Section 32.5):** at consultation time, the tool auto-launches, in order: (1) the doctor's own approved variant for that condition, if `doctor_content_preferences` has one — her contribution is always her default; (2) otherwise, the shared library's highest-`usage_count` approved variant. Never a picker. Browsing or switching to any other approved variant — including ones authored by other doctors in her specialty — is available as a lightweight, optional action outside the live consultation, never as a required step in the room. This gives each doctor a version of the library that feels like her own by default, while still pooling everyone's contributions into one shared, growing asset underneath.

A variant is only eligible to appear in a live consultation or the patient portal when `status = approved`. Nothing in `pending_review`, `rejected`, or `archived` state is ever shown to a patient. Doctors browsing the library see variants by content quality/usage, never by "who made it" — no attribution is surfaced anywhere in the doctor-facing or patient-facing UI. Reviewer identity (`reviewed_by`) exists for internal audit and accountability only, and is never displayed.

**Multiple approved variants can coexist for the same condition** — no single "winner" needs to be picked. Doctors aren't designers, and different valid explanations of the same condition are a feature, not a conflict to resolve. The library grows by addition, not by argument.

### 32.4 Provider abstraction
Add an `AnimatedAnatomyProvider` interface alongside the provider list in Section 43. It wraps the SVG/GSAP rendering + Fabric.js annotation layer. Business logic must not hard-depend on the specific rendering approach — this keeps the door open to a future `ThreeDAnatomyProvider` implementation (Section 32.2) without touching consultation or portal code.

### 32.5 In-consultation UX constraints (this is where most "innovative" health-tech features die)
- Must add near-zero time to a 5–7 minute consultation. One tap to launch the relevant visual from the condition already on record; no manual search during the visit.
- Must work on whatever device the clinic already has — tablet or the same desktop/laptop used for EMR — no new hardware requirement for MVP. AR/VR headsets are explicitly out of scope until there's proven pull.
- Doctor annotation must be lightweight (tap-to-mark, simple freehand, short voice note) — never a separate authoring tool that feels like extra admin work.
- Everything shown to the patient during the visit must auto-save to their portal without extra doctor action — the value compounds only if capture is automatic.

### 32.6 Patient portal integration
Covered in Section 23.1.

### 32.7 Monetization
Position this as the flagship differentiator of the Growth and White Label plans (Section 33), not a cheap add-on — it is the reason a clinic pays more than a bare-bones booking app charges. Track `education_sessions` as a usage/entitlement dimension alongside WhatsApp/SMS/AI usage (Section 34). The *conversation* about content in Section 32.8 happens for every clinic regardless of subscription tier — it costs nothing to discuss and doesn't require special-casing. Whether the clinic can actually *use* the feature live (education_sessions in consultation, patient portal delivery) is gated by their plan entitlement.

### 32.8 Specialty Content Onboarding Workflow (folded into the standard white-label onboarding conversation)

Every clinic already goes through a white-label branding/customization conversation during onboarding (Sections 14, 40). The Visual Health Advisor content discussion is a standard line item in that same conversation — there is no separate pilot, trigger, or "founding partner" motion to manage. This is how `anatomy_content_items` gets populated and continuously improved, largely automated by Claude Code with exactly one human checkpoint that is a clinician, not the product owner.

**Branch A — specialty already has an approved library (steady state, most clinics over time):**
1. During onboarding, show the doctor the existing approved variant(s) for her specialty's conditions — no attribution shown, just the content itself, defaulted per Section 32.3's selection rule (her own variant if she has one, otherwise the shared library's most-used).
2. Ask what's missing or what she'd add. This is a review/gap conversation, not a from-scratch build — low cost, fast.
3. Missing conditions: log as a `content_requests` row scoped to her clinic and run the full coverage-audit → compose → review loop (Branch B, steps 2–4) for the delta only.
4. If she'd explain something differently than the existing variant(s): her version is composed and submitted as a **new `anatomy_content_variants` row** (`status = pending_review`) against the same `content_item_id` — never an edit to or replacement of the existing variant. A lightweight clinical check (is it accurate, is it clear) either approves it as an additional live variant or sends it back. This is how the library gets richer, fast: every doctor who engages is a chance to add a new valid explanation, nothing is overwritten, nothing requires anyone to "win" a comparison, and usage naturally surfaces which variants doctors actually prefer over time.

**Branch B — first clinic in a new specialty (seeds the shared library):**
1. During onboarding, get her list of the ~15–25 conditions she treats most often. Log as `content_requests` (`status = intake`, `clinic_id` = hers initially).
2. **Coverage audit (automated).** Check source libraries (SMART, Health Icons, Open Science Art) per condition: usable source art / composable from generic base art / no usable source. Surface the gap list to her directly in the same conversation — never discover missing coverage after promising delivery. In practice, expect roughly half of a specialty's condition list to be straightforward compositing from an existing specialty kit, a third to need compositing across two adjacent kits (e.g., ENT + Digestive for reflux-related conditions), and a small number to be genuine gaps (mechanism/process illustrations with no ready stock source) worth flagging explicitly rather than promising and missing.
3. **Compose, don't draw.** Generate the interactive SVG/GSAP visual by compositing and animating existing licensed layers (Section 32.2) — never text-to-image generation for clinically-authoritative content. `license_source` auto-populated on the new `anatomy_content_variants` row, `status = pending_review`.
4. **Clinician review.** She reviews in an internal approve/reject/edit dashboard — two included revision rounds; further changes are a scoped paid content update. On approval: `status = approved`; `reviewed_by`/`reviewed_at` recorded internally, never shown to her or future doctors.
5. **Publish to the shared library.** The variant becomes available to her clinic immediately and the underlying `content_item` is added to the specialty-wide shared library (`content_requests.clinic_id = null` variant), so every future clinic in that specialty lands in Branch A instead of Branch B, and can add further variants of their own rather than being stuck with only the first one composed.

This is the actual answer to "how does an AI coding tool build medically-credible content without the founder sourcing images by hand": Claude Code automates sourcing, composition, tagging, variant management, and the review-dashboard UI; a licensed clinician is the only step that can't be automated, and her job is a bounded review of one new variant at a time — never a comparison against, or a rewrite of, what another doctor already contributed.

### 32.9 Legal/compliance guardrails (non-negotiable)
- Never let this feature imply diagnostic authority — it is explanatory, always doctor-initiated and doctor-attributed to the patient (even though internal attribution to individual clinicians is never shown between doctors, per Section 32.3).
- Licensed anatomical content must carry correct attribution and usage-rights tracking (`license_source` field) — do not scrape or reuse copyrighted medical illustrations without a license.
- Never claim automatic regulatory compliance (HIPAA/ISO/ABDM/etc.) for this feature; document what's implemented and what needs legal review, especially since this touches patient-facing medical content more directly than scheduling/CRM data does (see also Section 38).

---

## 33. SUBSCRIPTIONS AND MONETIZATION

Create a flexible entitlement system rather than hard-coded plan logic. Entities: `plans`, `features`, `plan_features`, `subscriptions`, `entitlements`, `usage_events`, `usage_counters`.

Initial plans may include Core, Growth, White Label, and Enterprise.

Potential entitlements: doctors, staff, locations, storage, WhatsApp messages, SMS, email, AI usage, website, CRM, automation, analytics, custom domains, white-label, API, SSO, and **visual patient-education sessions** (Section 32.7).

Support monthly billing, annual billing, trials, grace period, cancellation, feature entitlements, usage limits, invoices, and payment history.

Do not immediately delete or lock patient data after non-payment. Use active, grace_period, read_only, suspended, and cancelled states with appropriate data export.

---

## 34. USAGE AND UNIT ECONOMICS

Track variable costs for WhatsApp, SMS, Email, AI, Storage, Additional users, Additional locations, and API usage.

The platform should eventually calculate: subscription revenue - provider costs - infrastructure allocation = gross margin.

Build usage tracking from the beginning even if billing is initially simple.

---

## 35. MULTI-LOCATION SUPPORT

Support organizations with multiple locations. Doctors may work at multiple locations. Appointments must be associated with organization, location, doctor, and patient.

Allow future reporting by location, doctor, service, and acquisition source.

---

## 36. DOMAIN ONBOARDING

Flow: enter domain → normalize → check uniqueness → generate verification token → display DNS instructions → verify ownership → add domain to Vercel through server-side provider → confirm SSL/domain status → activate → publish branded website.

Create `VercelDomainProvider` and `MockDomainProvider`. Never expose Vercel credentials to client-side code.

**Environment variables:** `DATABASE_URL` and `DATABASE_URL_UNPOOLED` (Neon, pooled and direct connections), `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET_NAME`, `BETTER_AUTH_SECRET`, `BETTER_AUTH_URL`, `VERCEL_API_TOKEN`, `VERCEL_PROJECT_ID`, `VERCEL_TEAM_ID`, `PLATFORM_ROOT_DOMAIN`. Never expose R2 secret keys or the unpooled `DATABASE_URL` in browser code (see also Section 51).

---

## 37. STORAGE

Use tenant-scoped paths such as `clinic_id/patient_id/document_id/file.ext`.

Use private buckets (Cloudflare R2, Section 4.2) for medical documents, prescriptions, and invoices. Public assets may be used for logos and public doctor images only when explicitly configured.

Private medical files must use signed URLs.

Validate file type, size, filename, MIME type, extension, and content. Provide a malware-scanning integration point.

Design storage behind the `StorageProvider` abstraction (Section 43) so large-scale archival storage can be moved to another provider later without touching business logic.

---

## 38. SECURITY

Implement RLS, RBAC, MFA-ready architecture, secure sessions, rate limiting, CSRF protections where applicable, CSP, secure headers, input validation, output encoding, secure file handling, audit logs, access logs, consent logging, privacy policy, data export, data deletion workflow, backup strategy, disaster recovery, and database migration strategy.

Never claim automatic HIPAA, ISO, SOC 2, ABDM, or legal compliance. Document which controls are implemented and which require external legal, operational, organizational, or infrastructure review.

Design for Indian healthcare usage and applicable Indian data-protection requirements without making unsupported legal claims.

---

## 39. ADMINISTRATION

**Platform Admin:** Clinics, organizations, domains, subscriptions, plans, feature configuration, usage, platform health, audit events, system events, customer health, suspension/reactivation, and global configuration. Impersonation must require explicit authorization, clear warning, audit logging, and time-bounded access where possible.

**Clinic Admin:** Clinic profile, branding, staff, doctors, services, locations, availability, communication templates, automation, billing, domain, integrations, and export.

---

## 40. ONBOARDING

New clinic flow: create account → enter clinic details → add doctors → add staff → add services → configure working hours → upload logo → configure branding → **discuss Visual Health Advisor content (Section 32.8, folded into the branding step)** → configure communication → optionally import patients → generate website → configure booking → configure domain → publish.

Target: clinic can become operational within approximately 30 minutes. Build progress indicators and setup completion percentage.

---

## 41. DATA IMPORT

Support CSV and Excel import for patients, doctors, appointments, and services.

Provide column mapping, preview, validation, duplicate detection, error report, and rollback where feasible.

Design this as a future sales feature: assisted migration from existing clinic software.

---

## 42. PERFORMANCE

Use Server Components by default, Client Components only where needed, proper database indexes, pagination, debounced search, caching, image optimization, asynchronous processing, per-tenant rate limiting, and usage monitoring.

Index frequently queried fields such as `organization_id`, `clinic_id`, `patient_id`, `domain`, appointment date, patient phone, and status.

Avoid N+1 queries. Do not load entire patient or appointment datasets into the browser.

---

## 43. OBSERVABILITY

Implement production observability for application errors, failed actions, failed jobs, database errors, external-provider failures, webhook failures, tenant-specific error rates, latency, usage, storage, and background jobs.

Every important external operation should have an identifiable request/job/event ID.

---

## 44. BACKUPS AND DISASTER RECOVERY

Define database backup strategy, restore procedure, storage backup strategy, migration rollback, incident procedure, and recovery objectives.

Do not claim disaster recovery merely because backups exist. Document actual RPO, RTO, and restore testing procedure.

---

## 45. PROJECT STRUCTURE

```
src/
  app/
    (platform)/
    (tenant)/
    _internal/
  components/
  features/
    auth/
    tenants/
    organizations/
    clinics/
    patients/
    appointments/
    prescriptions/
    billing/
    crm/
    outreach/
    automation/
    analytics/
    ai/
    domains/
    branding/
    subscriptions/
    integrations/
    health-graph/       <- Family Health Graph (Section 7)
    education/           <- Visual Health Advisor Layer (Section 32)
  lib/
    db/                  <- Neon/Postgres access (renamed from "supabase")
    auth/                <- Better Auth integration + JWT-session bridge (Section 9.1)
    tenants/
    permissions/
    validation/
    providers/
    events/
    storage/              <- Cloudflare R2 via StorageProvider (Section 37)
  server/
    actions/
    services/
    jobs/
  types/
  config/
```

Maintain clear boundaries between UI, server actions, services, database access, tenant resolution, authorization, providers, events, automation, and AI.

---

## 46. PROVIDER ABSTRACTIONS

Create interfaces for `WhatsAppProvider`, `SMSProvider`, `EmailProvider`, `PaymentProvider`, `DomainProvider`, `AIProvider`, `StorageProvider`, and `AnimatedAnatomyProvider` (Section 32.4).

Provide mock implementations for development and testing. Business logic must not depend directly on one provider — this is what makes the Neon/R2/Better Auth stack choice (Section 4) swappable later without a rewrite (Section 4.4).

---

## 47. TESTING REQUIREMENTS

Automated tests MUST prove tenant isolation, domain resolution, authentication boundaries, booking correctness, communication behavior, billing verification, and security properties.

**Tenant tests:** Clinic A cannot read or update Clinic B data or documents, even through hidden fields.

**Domain tests:** correct branding per domain; unknown, unverified, and suspended domains handled safely.

**Booking tests:** public booking works, conflicts are prevented, tenant attribution and source attribution are preserved.

**Communication tests:** tenant scoped, opt-out respected, failed providers retried appropriately, duplicate automation execution prevented.

**Billing tests:** payment verification is server-side and webhook processing is idempotent.

**Security tests:** authentication secrets never reach the browser, private storage is not public, unsafe branding input is rejected, and the RLS/session-variable bridge (Section 9.1) is independently tested for both success and failure cases.

---

## 48. PRODUCT ACCEPTANCE TEST

A new clinic must be able to: create account → complete onboarding → add doctor → add services → configure availability → upload logo → generate website → publish website → receive visitor enquiry → create lead → contact lead → book appointment → send confirmation → send reminder → patient arrives → complete consultation → create prescription → generate invoice → record payment → schedule follow-up → send reminder → patient returns → dashboard records conversion → clinic owner sees performance.

This complete workflow must be covered by integration/end-to-end testing.

---

## 49. MVP SCOPE

**Clinic Operations:** Auth, tenant management, doctors, staff, patients, appointments, prescriptions, invoices, payments, dashboard.

**Growth (reframed):** Clinic website, online booking, lead capture, basic CRM, WhatsApp, reminders, follow-ups, source attribution, basic analytics, **plus household linking and condition-tagging on the patient record** (the minimum Family Health Graph needed so Phase 2 has structured data to attach to from day one — do not defer this, or Phase 2 will require a costly data-migration/backfill).

**White Label:** Branding, custom domains, branded invoices/prescriptions/emails.

**SaaS:** Subscriptions, entitlements, usage tracking, platform admin.

**Explicitly NOT in Phase 1 MVP:** any visualization content, `anatomy_content_items`, `education_sessions`, or the in-consultation visual tool. Phase 1's only job regarding Phase 2 is to make sure the data model doesn't need surgery later.

---

## 50. GO-TO-MARKET NARRATIVE (for sales/marketing use, not engineering)

Pitch to a clinic owner should not lead with "manage your patients better." It should lead with:

> "Your patients forget 80% of what you tell them in a 5-minute consultation. Clinic Growth OS gives you a one-tap visual to show them what's actually happening in their body — and it stays in their pocket afterward, with your clinic's name on it, in their language. That's why they come back to *you*, and why they tell their family to come to *you* too."

Competitive comparison to use in sales collateral: every other clinic CRM in the Indian market sells scheduling + reminders + a website. None of them sell the doctor a tool to increase patient comprehension in the room. That is the wedge, and it should be the headline in every demo, not a Phase 2 footnote.

---

## 51. IMPLEMENTATION PROCESS

Before writing code: inspect repository, identify Next.js version and routing model, identify database access patterns, inspect database schema, identify authentication, identify existing functionality, do not destroy existing functionality, identify technical debt, propose migration plan, identify assumptions, identify unresolved product decisions, produce architecture diagram, produce implementation roadmap.

Do not immediately generate hundreds of files. Implement incrementally.

---

## 52. ITERATIVE DEVELOPMENT RULE

After every major feature: run TypeScript checks, linting, unit tests, integration tests, database migration validation, RLS tests, tenant-isolation tests, and secret-exposure checks.

Then report: files created, files modified, database changes, environment variables added, tests added, tests passed, known issues, and next recommended step.

Do not claim a feature is complete without validating it.

---

## 53. SECURITY-FIRST DEVELOPMENT RULES

Never: trust client-provided tenant IDs; rely on frontend filtering; expose auth secrets or storage credentials to the browser; put privileged database operations in client components; expose permanent URLs for private medical documents; trust browser payment status; allow arbitrary JavaScript through branding; use mock security as production security; silently bypass RLS; or use platform-admin privileges for ordinary clinic operations.

---

## 54. UX PRINCIPLES

The product should feel modern and simple. Prioritize mobile responsiveness, fast navigation, minimal clicks, clear empty states, meaningful loading states, useful error states, contextual actions, keyboard accessibility, accessible forms, readable typography, and a consistent design system.

Receptionist workflow: speed. Doctor workflow: minimal administrative burden. Owner workflow: business outcomes. Patient workflow: minimal friction.

---

## 55. PRODUCT ANALYTICS

Track SaaS metrics: activation, trial-to-paid conversion, MRR, ARR, churn, retention, LTV, CAC, ARPU, gross margin, feature adoption, and DAU/WAU/MAU.

Track tenant health: login frequency, appointments, patient creation, messages, website traffic, bookings, revenue, and feature usage — and, specific to this product's thesis, **family retention rate** and **visual-education session adoption per doctor**.

Create a tenant health score for future customer-success workflows.

---

## 56. INFRASTRUCTURE STRATEGY

Initial infrastructure: Vercel Pro, Neon (Section 4.1), Cloudflare R2 (Section 4.2), external messaging providers, external payment provider, and external AI provider when enabled.

Do not prematurely introduce dedicated infrastructure. Optimize for the first 100+ paying clinics.

The architecture must allow future scaling to larger Neon compute tiers, read replicas, dedicated queues, additional object storage capacity, advanced observability, and enterprise infrastructure. For enterprise customers, support an upgrade path to dedicated infrastructure.

---

## 57. COST CONTROL

Design for predictable unit economics. Track per-tenant database usage where practical, storage, bandwidth, messages, AI usage, email, SMS, WhatsApp, users, and locations.

Do not offer unlimited expensive third-party resources on low-cost plans without modelling the economics. Neon's scale-to-zero and R2's zero-egress model are specifically chosen to keep pre-revenue development cost near $0 while remaining genuinely scalable once paid plans begin (Sections 4.1–4.2).

---

## 58. ENVIRONMENT MANAGEMENT

Separate development, preview, staging, and production. Never use production secrets in local development. Document all environment variables (Section 36). Provide `.env.example`. Never commit secrets.

---

## 59. REQUIRED DELIVERABLES

1. Product architecture
2. Mermaid architecture diagram
3. Domain model
4. Database schema (including Family Health Graph and Visual Health Advisor entities from Section 6)
5. Neon migration SQL
6. RLS policies, including the JWT→session-variable bridge (Section 9.1)
7. Domain-resolution utility
8. Next.js Proxy implementation
9. Tenant context utilities
10. RBAC/permission system
11. Branding system
12. Website Studio foundation
13. Public booking flow
14. Patient CRM (with Family Health Graph integration)
15. Appointment system
16. Prescription system
17. Billing system
18. Communication provider abstractions
19. Automation architecture
20. Event architecture
21. AI provider abstraction
22. Subscription/entitlement model
23. Platform admin
24. Clinic admin
25. Patient portal foundation (including "My Health, Explained" tab scaffold)
26. Mock providers, including `AnimatedAnatomyProvider`
27. Seed data for two clinics
28. Test suite
29. Environment documentation
30. Local development instructions
31. Vercel deployment instructions
32. Production security checklist
33. Backup/DR checklist
34. Scaling strategy
35. Cost assumptions
36. Known limitations
37. Future roadmap
38. Specialty Content Onboarding Workflow implementation (Section 32.8)

---

## 60. SEED DATA

Create two example tenants: ABC Clinic (`abcclinic.example.com`) and XYZ Clinic (`xyzclinic.example.com`). They must have different branding, doctors, patients, services, and appointments. Include at least one household with multiple linked patients and one tagged `health_condition` per tenant, to exercise the Family Health Graph. Tests must prove strict isolation.

---

## 61. FINAL DESIGN PRINCIPLE

When a design decision is uncertain: prefer the safest option, simplest maintainable architecture, server-side authorization, tenant isolation by construction, asynchronous processing for non-critical side effects, extensible provider interfaces, configuration over hard-coded rules, measurable product outcomes over feature quantity, and mobile-first workflows.

Do not build the biggest clinic software. Build a simple, secure, scalable Clinic Growth OS that clinics will pay for because it helps them run the practice, grow the practice, and become the practice their patients trust more than anywhere else.

---

## 62. HOW THIS DOCUMENT IS USED ACROSS TOOLS AND COLLABORATORS

Claude Code is the primary AI coding tool for this project, used from VS Code (the primary IDE, whether via terminal or the Claude Code VS Code extension). Collaborators may use other AI-IDE tools — Antigravity, Cursor, or others — inside VS Code or standalone. This section exists so every tool and every collaborator works from one shared spec instead of quietly diverging interpretations of the architecture.

### 62.1 One canonical source of truth, checked into the repo as text
This document is the spec. It must live in the repository as plain Markdown, not only as a PDF handed out for reading — AI coding tools work from files in the repo, not from a PDF someone read once. Place the full document at `docs/MASTER_PROMPT.md` in the repo root. A PDF version may be generated from this Markdown source for stakeholder/investor/printed reference, but should never be edited independently — two versions of the truth is worse than one imperfect version.

### 62.2 Thin, tool-specific pointer files — content lives in one place, not many
Rather than duplicating instructions per tool (which drifts out of sync fast), each AI tool gets a short file at the repo root that points to the canonical spec and states the same core discipline:

- **`CLAUDE.md`** — read automatically by Claude Code. Points to `docs/MASTER_PROMPT.md`, restates the iterative rule from Section 52, and restates the security-first rules from Section 53.
- **`AGENTS.md`** — an increasingly common cross-tool convention that Antigravity and several other agentic coding tools read by default. Carries the same pointer and the same core discipline as `CLAUDE.md`, so a collaborator using a different tool is held to the identical standard rather than a looser one.
- **`.vscode/`** — shared workspace settings (formatter, linter, recommended extensions) so VS Code behaves consistently for every collaborator regardless of which AI tool they're pairing it with.

None of these pointer files should contain their own copy of the architecture, schema, or product decisions — they exist only to route every tool back to `docs/MASTER_PROMPT.md`, so an update to the spec never requires updating multiple tool-specific files in parallel.

### 62.3 The gate is the test suite, not the tool
Whichever AI tool a collaborator used to generate a change, the acceptance bar is the same: it must pass the automated tests required by Section 47 (TypeScript checks, lint, unit tests, integration tests, migration validation, and — non-negotiably — the RLS/tenant-isolation cross-access tests), and it goes through normal PR review before merging. The tool that wrote the code is never itself the approval; passing that suite is. This keeps quality consistent across a team using different tools, and specifically protects the tenant-isolation boundary described in Section 9, which is the one piece of this architecture where a shortcut taken by any single tool or collaborator could compromise every clinic's data, not just their own.

---

## 63. START HERE

Do NOT start by implementing the entire application, and do NOT start by implementing Phase 2.

First:
1. Inspect the repository (if one exists) and understand existing functionality; do not destroy it.
2. Produce the proposed architecture and database/entity model — **including the Family Health Graph additions from Section 6 in the first migration**, even though the UI for it ships later.
3. Identify the Phase 1 MVP boundary using Section 49.
4. Identify assumptions and unresolved product decisions — in particular, which specialty will seed the shared content library first, based on the first design-partner clinic's actual specialty (Section 32.8).
5. Produce the implementation sequence and wait for approval before beginning large-scale implementation.

**First implementation milestone:** Authentication + Multi-tenancy + Tenant resolution + RLS + RBAC + Clinic onboarding + Basic clinic shell + Basic patient/appointment foundation — with `households`, `patient_household_links`, and `health_conditions` included in the initial schema, and the JWT→Postgres-session RLS bridge from Section 9.1 proven out as an early spike before the rest of the schema is built on top of it.
