# Church Digital Platform Constitution

## Core Principles

### I. Test-First (NON-NEGOTIABLE)
Every behavior change ships as: failing test → verify red → minimal implementation → verify green → commit. Never skip test steps. SQL tests run transactionally (`BEGIN ... ROLLBACK`) with explicit fixtures and are registered in `supabase/tests/run_all.sql`.

### II. Security by Default
All state transitions in `SECURITY DEFINER` RPCs with the REVOKE-then-grant privilege pattern. RLS on every table with explicit role targeting and tenant checks. Role authorization reads `users.role` via service-role client — never user-editable metadata; lookup failures fail closed (403). Secrets live only in environment/vault — zero credential literals or fallbacks in code.

### III. Forward-Only Migrations
Never edit an applied migration in place; changes ship as new forward migrations (`00XX_*.sql`). Feature migrations contain only their feature's changes — general hardening gets its own migration and test. `videos`, `payments`, and other applied tables are additive-only territory.

### IV. Arabic-First
The product language is Arabic: UI, error messages (`message_ar` catalog), alt text, announcements. Arabic strings and EGP prices are preserved verbatim. Error codes are frozen English tokens for machines; humans see Arabic.

### V. Deep Modules, Thin Handlers
Cross-cutting behavior (auth, error shaping, payment gateway) lives behind small shared seams (`_shared/http.ts`, `_shared/paymob.ts`); function handlers stay thin adapters. One adapter per external concern; duplication is a defect.

## Product Truth (owner-ratified 2026-08-17)

- **Single church** deployment. Tenant scaffolding stays internal; no multi-church UI or data entry ever ships.
- **Paymob is the only payment rail** (electronic wallets + Visa).
- **Event Booking with Extra Services** (specs 007 & 008) replaces all video delivery machinery (decommissioned 2026-08-17): separate `event_types` and `extra_services` tables, venue/resource exclusion constraints on `(resource_id, tstzrange)`, review-first-then-pay lifecycle (`SUBMITTED → CONFIRMED/REJECTED → PENDING_PAYMENT → PAID`), price snapshots on selected extras, and dual payment support (Paymob online + admin cash RPCs).
- **Booking confirmation call is mandatory**: bookings wait in `AWAITING_CALL` until an admin confirms by phone (order-processing model); state machine `PENDING_PAYMENT → AWAITING_CALL → CONFIRMED → COMPLETED`.
- **Error contract**: `{"error": CODE, "message_ar": "…"}` — codes frozen from feature 003; Arabic messages data-editable.

## Development Workflow

- Specs in `specs/` are the feature source of truth (speckit flow: specify → clarify → plan → tasks → implement).
- Implementation loop: fast model implements from tasks.md; reviewer verifies against spec + AGENTS.md locked decisions with the two-axis review.
- Commits: `feat(scope):` / `fix(scope):` / `test(scope):`, one logical change each, on feature branches.
- One speckit command at a time across concurrent sessions (`.specify/feature.json` is a single shared pointer).

## Governance

Constitution supersedes ad-hoc practice; AGENTS.md Locked Decisions are the enforcement detail. Amendments require an owner decision recorded in `docs/adr/` and a date bump below.

**Version**: 1.1.0 | **Ratified**: 2026-08-17 | **Last Amended**: 2026-08-19
