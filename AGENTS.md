# AGENTS.md

## Overview

Planning workspace (docs only, no app code) for Egyptian Coptic church digital platform (Flutter mobile + Flutter Web admin on Supabase). Implementation plans = source of truth. One commit; `docs/superpowers/` untracked.

## Core Files

- `docs/superpowers/plans/2026-08-05-church-digital-platform.md` — master blueprint: decisions A1–A11, data model, booking state machine, 12-week roadmap, costs, risks
- `docs/superpowers/plans/conventions.md` — conventions (slot locking, RLS/RPC rules, edge-function pattern, outbox pattern, enums)
- `docs/superpowers/plans/2026-08-05-phase0-foundations.md` → `phase1-mvp` → `phase2-analytics` — TDD task plans; migrations: 0001–0003 (P0), 0004–0021 (P1), 0022–0030 (P2)
- `docs/external-onboarding-checklist.md` — external dependencies critical path (Paymob/Meta/YouTube/Play)

## Protocol

1. Read master plan §1 + `conventions.md` + `docs/agents/*.md` before edit.
2. One Task at a time. Read only active task section.
3. Test-first: Step 1 write failing test → implement → run → PASS → commit. Never skip test steps.

## Locked Decisions

- **NO live streaming**: Recorded events → YouTube **unlisted** videos. Sold via Paymob + WhatsApp. `videos.update` requires **OAuth2 bearer** (refresh token exchange, secrets `GOOGLE_CLIENT_ID/SECRET/REFRESH_TOKEN`). No API keys for write.
- **Backend = Supabase**: Postgres 16 + RLS + PostgREST + Deno Edge Functions + pg_cron. No NestJS/Redis/VPS.
- **Slot lock**: `SELECT ... FOR UPDATE` on `service_slots` + active-booking count vs `capacity` inside `book_slot()`. No unique partial index for slot capacity. `v_available_slots` returns `AVAILABLE|BOOKED|CLOSED`.
- **State RPCs & Outbox**: State transitions in `SECURITY DEFINER` RPCs. Secrets in edge functions/vault. `whatsapp_outbox` drain: 100 rows/run, batches of 10, cron 1 min.
- **Payment race**: `apply_payment` on stale/cancelled booking sets `REFUND_PENDING` + enqueues `refund_requests` (no seat granted).
- **Migration Upgrade Path**: Never modify past applied migrations in place without creating a corresponding new forward migration (`00XX_*.sql`) so `supabase db push` applies changes on existing environments.
- **Edge Function Defense**: Validate Bearer auth token on all checkout/protected endpoints. Wrap external upstream JSON parsing in try/catch to set payment status `FAILED` and return 502 `UPSTREAM_ERROR`. Webhook positive integer validation and `PAID` status idempotency mandatory.
- **Admin UI Role Guard**: Admin routes must strictly require non-null `role` from `ADMIN|PRIEST|SUPER_ADMIN`.
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

## Commands

- Local stack: `npx supabase start` / `npx supabase db reset`
- SQL tests: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/XXXX_name.sql`
- Edge functions: `deno test --allow-env supabase/functions/<name>/`
- Flutter: `flutter test apps/mobile/test/...`

## Gotchas

- `session-ses_02d3.md` root = stray dump. Ignore.
- Plan files untracked in git. Stage/commit only when asked.
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
8. **Diagrams sync**: update master plan §6 state machine when adding enum/transition.
9. **Schema sync**: update master plan §5 schema list when adding table.
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
