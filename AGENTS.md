# AGENTS.md

## Overview

Monorepo for a **single** Egyptian Coptic church digital platform (Flutter mobile + Flutter Web admin on Supabase backend). `specs/` (speckit) + `.specify/memory/constitution.md` = feature/product source of truth; `docs/superpowers/plans/conventions.md` = engineering conventions. Single-church deployment: tenant scaffolding stays internal, never exposed in UI or data entry.

## Core Files

- `docs/superpowers/plans/conventions.md` — conventions (slot locking, RLS/RPC rules, edge-function pattern, outbox pattern, enums). Sole surviving doc in `plans/`; dated plan files were removed 2026-08-17 (history in git).
- `specs/` — speckit feature specs = feature source of truth (003 edge kernel, 004 accessibility + video delivery, 005 admin domain, 006 mobile domain); `.specify/memory/constitution.md` — project constitution.
- `docs/adr/` — architecture decision records (ADR 0001 domain model).
- `docs/external-onboarding-checklist.md` — external dependencies critical path (Paymob/Meta/YouTube/Play)

## Protocol

1. Read `conventions.md` + `.specify/memory/constitution.md` + `docs/agents/*.md` before edit.
2. One Task at a time. Read only active task section.
3. Test-first: Step 1 write failing test → implement → run → PASS → commit. Never skip test steps.

## Locked Decisions

- **NO Video Payments — Event Booking with Extra Services** (owner decision 2026-08-17): Personal filmed-video and video catalog payment features are cancelled outright and decommissioned. Active replacement is **Event Booking with Extra Services** (specs 007 & 008) with separate `event_types` and `extra_services` tables, venue/resource exclusion constraints on `(resource_id, tstzrange)`, review-first-then-pay lifecycle (`SUBMITTED → CONFIRMED/REJECTED → PENDING_PAYMENT → PAID`), price snapshots on selected extras, and dual payment support (Paymob online + admin cash RPCs).
- **Backend = Supabase**: Postgres 16 + RLS + PostgREST + Deno Edge Functions + pg_cron. No NestJS/Redis/VPS.
- **Slot lock**: `SELECT ... FOR UPDATE` on `service_slots` + active-booking count vs `capacity` inside `book_slot()`. No unique partial index for slot capacity. `v_available_slots` returns `AVAILABLE|BOOKED|CLOSED`.
- **Booking Confirmation Call**: Bookings stay `AWAITING_CALL` (قيد التنفيذ) until an admin confirms by phone after calling — order-processing model. States `PENDING_PAYMENT → AWAITING_CALL → CONFIRMED → COMPLETED` (guarded by `bookings_status_guard`; confirmation via `transition_booking_status`).
- **Arabic Error Contract**: All client-facing errors use `{"error": CODE, "message_ar": "…"}` — codes frozen (`UNAUTHORIZED|FORBIDDEN|BAD_REQUEST|UPSTREAM_ERROR|INTERNAL`), Arabic sentences from the `error_messages` catalog (5-min edge cache, `FALLBACK` fail-safe). Clients display `message_ar`, never raw codes.
- **State RPCs & Outbox**: State transitions in `SECURITY DEFINER` RPCs. Secrets in edge functions/vault. `whatsapp_outbox` drain: 100 rows/run, batches of 10, cron 1 min.
- **Payment race**: `apply_payment` on stale/cancelled booking sets `REFUND_PENDING` + enqueues `refund_requests` (no seat granted).
- **Migration Upgrade Path**: Never modify past applied migrations in place without creating a corresponding new forward migration (`00XX_*.sql`) so `supabase db push` applies changes on existing environments.
- **Edge Function Defense**: Validate Bearer auth token on all checkout/protected endpoints. Wrap external upstream JSON parsing in try/catch to set payment status `FAILED` and return 502 `UPSTREAM_ERROR`. Webhook positive integer validation and `PAID` status idempotency mandatory.
- **Admin UI Role Guard**: Admin routes must strictly require non-null `role` from `ADMIN|SUPER_ADMIN` (PRIEST tier removed from schema — see `docs/adr/0002-video-to-event-booking-pivot.md` + spec 009 US5).
- **RLS & Storage Policy Guard**: Admin mutation policies on all tables and `storage.objects` must include `public.is_admin()`. Migrations creating bucket policies must run `ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;`. Target roles explicitly with `TO authenticated` or `TO anon, authenticated`. Tables must use `public.tenant_id()` default and tenant check (`tenant_id = public.tenant_id()`). Use granular DML grants (`SELECT, INSERT, UPDATE, DELETE`)—never `GRANT ALL`. No `CREATE INDEX CONCURRENTLY` in migration files.
- **RLS Test Semantics**: Unauthorized `UPDATE`/`DELETE` tests must assert 0 rows affected (`ROW_COUNT = 0` / `is(...) = 0`), not exceptions. Test users must update `public.users.role` (not `public.profiles`). All test scripts must be transactionally isolated (`BEGIN ... ROLLBACK`).
- **Pre-Commit Code Audit**: Never blindly trust prompt/template SQL snippets. Verify every policy for missing role gates, hardcoded tenant IDs, and overbroad grants before committing.
- **Test Runner Registration**: Every test in `supabase/tests/` MUST be registered in `supabase/tests/run_all.sql` with `\ir`.
- **Direct Repository Testing**: Unit tests must instantiate and invoke the real repository/service class with fake/mock clients—never test duplicate private parsing helpers in isolation. Test fakes must be slot-aware.
- **Repository Seams & Errors**: Single unified write seam per flow (`reserveAndPay`). Hide internal pipeline steps (`createCheckout`). Return `Either<Failure, Success>` with zero raw `PostgrestException` or `UnimplementedError` leaks. No dead parameters. Free checks must strictly verify `paidAmount == 0`.
- **Startup Fail-Fast**: `main.dart` in mobile and admin apps must validate `SUPABASE_ANON_KEY` and throw `StateError` if empty.
- **Function Privilege Hardening**: Every restricted `SECURITY DEFINER` function must explicitly `REVOKE ALL ON FUNCTION public.<func_name>(<args>) FROM PUBLIC, anon, authenticated;` before granting to `service_role`.
- **Identity Sequences**: Tables using `GENERATED ALWAYS AS IDENTITY` accessible to client inserts must grant `USAGE, SELECT` on their generated sequence to `authenticated`.
- **Negative Authorization Verification**: SQL tests for restricted functions must assert execution denial for unprivileged roles (`anon`, `authenticated`).
- **Role Verification Invariant**: Edge function auth seams MUST enforce `users.role` directly from Postgres with service-role privileges. No metadata fallbacks. Role lookup errors fail closed with 403 `FORBIDDEN`.
- **Zero-Leak Error Contract**: Edge functions must return standard JSON `{"error": CODE}` for all 500 errors with zero `message` payload containing runtime exceptions.
- **RPC Money Boundaries**: `payments` table status transitions are forbidden from direct DML in edge functions; must call `SECURITY DEFINER` RPCs (`apply_payment`, `mark_payment_refunded`).

## Commands

- Local stack: `npx supabase start` / `npx supabase db reset`
- SQL tests: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/XXXX_name.sql`
- Edge functions: `deno test --allow-env supabase/functions/<name>/`
- Flutter: `flutter test apps/mobile/test/...`

## Gotchas

- `session-ses_02d3.md` root = stray dump. Ignore.
- Dated plan files were deleted 2026-08-17 (git history preserves them); `conventions.md` is the only surviving doc in `docs/superpowers/plans/`. Stage/commit deletions when asked.
- Direct edit critical/plan files; do not delegate large writes.
- Arabic strings & prices in EGP kept as-is.
- SQL skills: `.agents/skills/supabase` and `.agents/skills/supabase-postgres-best-practices`.

## Plan-Writing Checklist

1. **Enum sync**: enum values in SQL/RPCs must exist in BOTH `conventions.md` §Enums AND Phase 0 `0001_init_schema.sql` `CREATE TYPE`. Back-propagate additions to Phase 0.
2. **RLS = 2 statements**: `CREATE TABLE` requires `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;` BEFORE `CREATE POLICY`.
3. **Fixtures mandatory**: explicit `INSERT` statements in test files.
4. **Exact column names**: copy from `CREATE TABLE` migration, not memory.
5. **Empty-DB edge case**: `IS NULL`/`NOT EXISTS` needs age guard (`created_at < now() - interval`).
6. **Unique index names**: grep existing migrations before naming.
7. **No permanent stubs**: placeholder (`RETURN true`) needs `-- TODO(phase X, task Y)` + failing test.
8. **Diagrams sync**: update the owning feature's `specs/<feature>/data-model.md` state machine when adding enum/transition (master-plan diagrams removed 2026-08-17).
9. **Schema sync**: update the owning feature's `specs/<feature>/data-model.md` when adding a table.
10. **Exact filenames**: include date prefix (`2026-08-05-`) in references.
11. **Sequence permissions**: add sequence grant for `IDENTITY` tables.
12. **Revoke PUBLIC**: use `REVOKE ALL ... FROM PUBLIC, anon, authenticated;` for restricted RPCs.
13. **Test Runner Sync**: Every new test file in `supabase/tests/` must be registered in `supabase/tests/run_all.sql` with `\ir`.
14. **Storage RLS & Grants**: Migrations provisioning buckets must explicitly run `ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;` and grant granular DML (`GRANT SELECT ON storage.buckets`, `GRANT SELECT, INSERT, UPDATE, DELETE ON storage.objects TO authenticated`).
15. **Tenant Invariant**: All multi-tenant tables must define `tenant_id BIGINT NOT NULL DEFAULT public.tenant_id()` and enforce `tenant_id = public.tenant_id()` on all policies.

## Caveman Mode (ULTRA) — ALWAYS ON

Always respond in caveman ULTRA mode. Extreme brevity. Zero fluff.
- Drop all articles (a/an/the), filler words, pleasantries, hedging, connective phrases.
- Telegraphed fragments only. Short synonyms. Exact technical terms/code unchanged.
- Pattern: `[Thing] [action] [reason]. [Next step].`
- Auto-Clarity: normal prose only for critical security warnings or destructive actions.
