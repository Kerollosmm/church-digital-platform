# GEMINI.md — Monorepo Rules & Multi-Project Guidelines

## Caveman Mode (ULTRA) — ALWAYS ON

Respond in caveman ULTRA mode always. Extreme brevity. Zero filler.
- Drop articles, pleasantries, padding. Telegraphed fragments only. Technical terms/code exact.
- Pattern: `[Thing] [action] [reason]. [Next step].`

---

## Overview (3 Projects + Blueprint)

```
C:\church
├── apps/mobile/   [P1: User Mobile App] (Flutter Mobile - Android/iOS, Riverpod, GoRouter, FCM, Arabic RTL)
├── apps/admin/    [P2: Admin Dashboard] (Flutter Web PWA - Riverpod, Realtime subs, RBAC: Admin/Priest/SuperAdmin)
├── supabase/      [P3: Backend Services] (Postgres 16 + RLS + SECURITY DEFINER RPCs + Deno Edge Functions + pg_cron)
├── specs/         [Feature specs] (speckit: 003 edge kernel, 004 accessibility + video delivery, 005 admin domain, 006 mobile domain)
└── docs/          [REFERENCE] `conventions.md` (living rules), `docs/adr/` (decisions), external onboarding checklist — dated plan files removed 2026-08-17
```

---

## Routing & Scope

| Task / Feature | Target Directory | Stack & Tools |
| :--- | :--- | :--- |
| Schema, RLS, RPCs, triggers, audit log, slot locks, pg_cron | `supabase/migrations/` | Postgres 16 SQL, `psql` / pgTAP |
| Webhooks (Paymob, WhatsApp Meta, YouTube API, FCM, SMS) | `supabase/functions/` | Deno + TS, `deno test` |
| Parishioner mobile UI, booking flow, status display, push | `apps/mobile/` | Flutter Mobile, Riverpod, `supabase_flutter` direct, `flutter test apps/mobile/test` |
| Admin UI, booking management, overrides, refunds, realtime | `apps/admin/` | Flutter Web, Riverpod, Realtime, fl_chart, `flutter test apps/admin/test` |
| Conventions, RLS/RPC/outbox rules, enums | `docs/superpowers/plans/conventions.md` | Read-only reference |
| Feature specs, data models, contracts | `specs/<feature>/` | speckit docs (spec/plan/data-model/contracts/tasks) |

---

## Execution Rules

### 1. Backend (`supabase/`)
- **State Changes**: ALL inside `SECURITY DEFINER` RPCs. No direct client `INSERT`/`UPDATE` on business tables.
- **Slot Locking**: `SELECT ... FOR UPDATE` on `service_slots` + active booking count check vs `capacity`. No unique partial index on slot capacity.
- **RLS & Storage Invariants**: Every policy MUST declare explicit `TO authenticated` or `TO anon, authenticated`. Every admin mutation policy on tables or `storage.objects` MUST enforce `public.is_admin()`. Migrations with bucket policies must explicitly execute `ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;`. Multi-tenant tables MUST default `tenant_id` to `public.tenant_id()` and check `tenant_id = public.tenant_id()`. Use granular DML grants (`SELECT, INSERT, UPDATE, DELETE`)—never `GRANT ALL`. No `CREATE INDEX CONCURRENTLY` in migration files.
- **SQL & pgTAP Testing Invariants**: RLS `UPDATE` and `DELETE` on hidden rows modify 0 rows silently (no exception thrown)—assert `ROW_COUNT = 0` / `is(...) = 0`. Catch `SQLSTATE '42501'` on `INSERT` violations. User roles live in `public.users` (not `public.profiles`). Always wrap test runs in `BEGIN; ... ROLLBACK;` with isolated fixtures.
- **Test Runner Registration**: Every new SQL test in `supabase/tests/` MUST be registered in `supabase/tests/run_all.sql` with `\ir <filename>.sql`.
- **Pre-Commit Code Audit**: Never adopt user or template SQL blindly; inspect every line for missing `is_admin()` checks, hardcoded IDs, and overbroad grants before writing.
- **Integrations**: Paymob HMAC (SHA512 lowercase hex, param `hmac`) — Paymob is the ONLY payment rail (electronic wallets + Visa); WhatsApp outbox (100 rows/batch, cron 1 min); YouTube video expiry (OAuth2 bearer with refresh token exchange — secrets `GOOGLE_CLIENT_ID/SECRET/REFRESH_TOKEN`).
- **Video Model (owner decision 2026-08-17)**: TWO types. **Global**: public catalog, external YouTube links (never embedded), free or paid per video (`price = 0` free). **Personal**: per-booking filming add-ons (baptism/wedding) — `deliver_personal_video(p_phone, p_yt_url, p_title_ar, p_payment_id)`: exact `users.phone` match (`UNKNOWN_PHONE` refusal), PAID payment bound, idempotent, enqueues one `video_ready` WhatsApp outbox event. Title is the ONLY video metadata — NO caption/transcript fields anywhere.
- **Booking Confirmation Call**: Booking waits in `AWAITING_CALL` (قيد التنفيذ) until an admin confirms by phone — order-processing model. State machine: `PENDING_PAYMENT → AWAITING_CALL → CONFIRMED → COMPLETED`; confirm via `transition_booking_status` RPC.
- **Arabic Error Contract**: Client-facing errors are `{"error": CODE, "message_ar": "…"}` — codes frozen (`UNAUTHORIZED|FORBIDDEN|BAD_REQUEST|UPSTREAM_ERROR|INTERNAL`), Arabic from `error_messages` catalog (5-min edge cache, FALLBACK fail-safe).
- **Single Church**: One church in practice; tenant scaffolding internal only — never exposed in UI or data entry.
- **Webhook & Checkout Invariants**: Enforce positive integer `merchant_order_id`, protect `PAID` records from being overwritten by failure webhooks, require Bearer token auth before DB queries, and catch malformed upstream JSON (502 + mark FAILED).
- **Function Privilege Hardening**: PostgreSQL grants `EXECUTE` to `PUBLIC` by default. Every restricted `SECURITY DEFINER` RPC must explicitly execute: `REVOKE ALL ON FUNCTION public.<func_name>(<args>) FROM PUBLIC, anon, authenticated;` before granting to `service_role` or specific authorized roles.
- **Identity Sequences**: Tables using `GENERATED ALWAYS AS IDENTITY` with client insert policies must explicitly grant `USAGE, SELECT` on their generated sequence to `authenticated` (e.g. via `pg_get_serial_sequence` or schema sequence grant).
- **Negative Authorization Tests**: SQL regression tests for restricted RPCs must assert that unprivileged roles (`anon`, `authenticated`) receive permission denied (`SET LOCAL ROLE anon; ... EXCEPTION WHEN OTHERS THEN ...`).
- **Diagnostic & Test Script Hygiene**: Test scripts must never embed plaintext credentials, API keys, or fallback secret literals. Scripts must never execute network mutations on import—guard with `if (import.meta.main)` and require explicit `RUN_LIVE_TESTS=true` with safe deterministic in-memory fallback.
- **Edge Function Auth & Role Guard**: Role authorization MUST query public `users.role` exclusively using a hardened service-role client (`SUPABASE_SERVICE_ROLE_KEY`, never falling back to anon key). NEVER read or fall back to `user_metadata` or `app_metadata` (spoofable). Any lookup failure or throw MUST fail closed with 403 `FORBIDDEN`.
- **Zero Information Leak in 500 Responses**: HTTP 500 `INTERNAL` responses MUST NEVER contain raw exception messages, stack traces, or upstream payload snippets (`respond(500, "INTERNAL")` only). Log full details server-side via `console.error`.
- **Gateway Adapter Contracts**: Gateway and external API adapters (Paymob, Meta, FCM, YouTube) MUST return typed result unions (`{ ok: true, ... } | { ok: false, kind: "UPSTREAM_ERROR", status: number, message: string }`) instead of throwing generic errors. Handlers must inspect numeric status codes for retry decisions (`4xx` = non-retryable, `5xx` = retryable).
- **Financial State RPCs**: Every payment status change (`PAID`, `REFUNDED`, `FAILED`, `CANCELLED`) MUST execute via a dedicated `SECURITY DEFINER` SQL RPC with strict `REVOKE ALL ... FROM PUBLIC, anon, authenticated; GRANT ... TO service_role;`. Zero direct table `UPDATE` on `payments`.
- **Migration Scoping**: Feature migrations must contain ONLY changes required by that feature's specification. General performance optimizations, index additions, multi-seat triggers, and database-wide hardening must be isolated into dedicated forward migrations (`00XX_*.sql`) with their own registered pgTAP tests in `run_all.sql`.
- **Startup Fail-Fast**: Edge functions MUST validate all required environment variables at module initialization when started via `Deno.serve` and throw immediately if mandatory secrets are missing.
- **Migration Discipline**: Any function/schema edit requires both updating base migrations (for `db reset`) AND creating a new forward migration `00XX_*.sql` (for `db push` on existing databases).
- **Tests**: SQL: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/XXXX.sql`. Edge: `deno test --allow-env supabase/functions/<name>/`.

### 2. Mobile User App (`apps/mobile/`)
- **Arch**: Clean Architecture + Riverpod + GoRouter + `supabase_flutter` direct.
- **Localization**: Arabic-first (RTL mandatory).
- **API**: PostgREST views (`v_available_slots`, `v_my_bookings`) + `POST /rpc/<func>`.
- **Reliability**: Fail fast on missing `SUPABASE_ANON_KEY` in `main.dart`. Guard null payment IDs in purchase flows.
- **Repository Seams**: Single unified entry point for multi-step flows (`reserveAndPay`). Hide internal pipeline steps (`createCheckout`). Return `Either<Failure, Success>` with zero raw `PostgrestException` or `UnimplementedError` leaks.
- **No Dead Params**: Only declare parameters accepted by live RPCs. Free-tier bypass must check strictly `paidAmount == 0`.
- **Testing**: Test production repository classes directly with mocks/fakes. Test fakes must be slot-aware and deterministic.
- **Tests**: `flutter test apps/mobile/test/...`.

### 3. Admin Web (`apps/admin/`)
- **Arch**: Flutter Web PWA + Riverpod + Supabase Realtime (`postgres_changes`).
- **RBAC**: Enforce UI roles (`ADMIN`, `PRIEST`, `SUPER_ADMIN`). Never permit `role == null` on admin routes.
- **Realtime Cleanup**: Subscription unsubscribe in `ref.onDispose` must be async and wrapped in `unawaited()`.
- **Analytics**: fl_chart via `v_analytics_*` views; CSV export via `analytics-export` edge function.
- **Tests**: `flutter test apps/admin/test/...`.

---

## TDD & Clean Code

1. **TDD Flow**: Red (failing test) → Verify Fail → Green (minimal code) → Verify Pass → Commit (`feat:`, `fix:`, `test:`).
2. **SOLID & Quality**: Single responsibility, no magic values (use `conventions.md` enums), strict types, no swallowed errors.
3. **Superpowers & Skills**:
   - Check & invoke skills BEFORE action/edits.
   - Announce: `"Using [skill] to [purpose]"`.
   - Feature/Idea → `superpowers:brainstorming` | Bug → `superpowers:systematic-debugging` | Code → `superpowers:test-driven-development` | Multi-step → `superpowers:executing-plans`.

---

## Orchestration & Deep Thinking

- **Subagents**: Parallel dispatch for independent tasks. Focused prompts: file paths, checklist, structured output format. Kill idle agents immediately. Direct edit critical/plan files (no subagent delegation).
- **Research First**: `view_file` before edit (never edit blind). `grep_search` before assuming. Inspect `app_strings.dart` / screens for exact identifiers (zero hallucination).
- **Output**: Reports/reviews/checklists >1 paragraph → artifact file. Classify findings (CRITICAL / MAJOR / MINOR). Run verification before claiming pass.
