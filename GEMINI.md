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
└── docs/          [SOURCE OF TRUTH] Master plan (`2026-08-05-church-digital-platform.md`), `conventions.md`, phase plans
```

---

## Routing & Scope

| Task / Feature | Target Directory | Stack & Tools |
| :--- | :--- | :--- |
| Schema, RLS, RPCs, triggers, audit log, slot locks, pg_cron | `supabase/migrations/` | Postgres 16 SQL, `psql` / pgTAP |
| Webhooks (Paymob, WhatsApp Meta, YouTube API, FCM, SMS) | `supabase/functions/` | Deno + TS, `deno test` |
| Parishioner mobile UI, booking flow, status display, push | `apps/mobile/` | Flutter Mobile, Riverpod, `supabase_flutter` direct, `flutter test apps/mobile/test` |
| Admin UI, booking management, overrides, refunds, realtime | `apps/admin/` | Flutter Web, Riverpod, Realtime, fl_chart, `flutter test apps/admin/test` |
| Architecture decisions, state machines, API contracts | `docs/superpowers/plans/` | Read-only reference |

---

## Execution Rules

### 1. Backend (`supabase/`)
- **State Changes**: ALL inside `SECURITY DEFINER` RPCs. No direct client `INSERT`/`UPDATE` on business tables.
- **Slot Locking**: `SELECT ... FOR UPDATE` on `service_slots` + active booking count check vs `capacity`. No unique partial index on slot capacity.
- **Integrations**: Paymob HMAC (SHA512 lowercase hex, param `hmac`), WhatsApp outbox (100 rows/batch, cron 1 min), YouTube video expiry (OAuth2 bearer with refresh token exchange — secrets `GOOGLE_CLIENT_ID/SECRET/REFRESH_TOKEN`).
- **Webhook & Checkout Invariants**: Enforce positive integer `merchant_order_id`, protect `PAID` records from being overwritten by failure webhooks, require Bearer token auth before DB queries, and catch malformed upstream JSON (502 + mark FAILED).
- **Migration Discipline**: Any function/schema edit requires both updating base migrations (for `db reset`) AND creating a new forward migration `00XX_*.sql` (for `db push` on existing databases).
- **Tests**: SQL: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/XXXX.sql`. Edge: `deno test --allow-env supabase/functions/<name>/`.

### 2. Mobile User App (`apps/mobile/`)
- **Arch**: Clean Architecture + Riverpod + GoRouter + `supabase_flutter` direct.
- **Localization**: Arabic-first (RTL mandatory).
- **API**: PostgREST views (`v_available_slots`, `v_my_bookings`) + `POST /rpc/<func>`.
- **Reliability**: Fail fast on missing `SUPABASE_ANON_KEY` in `main.dart`. Guard null payment IDs in purchase flows.
- **Testing**: Test production repository classes directly with mocks/fakes—no duplicate test-only parser helpers.
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
