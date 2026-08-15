# Release-Blockers Security Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every CRITICAL release-blocker + scope blocker from the two 2026-08-10 architecture reviews (backend review `architecture-review-20260810-153503.html` + full-stack review `architecture-review-20260810-155139.html`) in one release gate, test-first, before further feature work.

**Architecture:** Backend-first. SQL owns money/state: privileged RPCs become service-role only, NULL-owner bypasses fixed, REFUNDED is terminal, complaints assignment via RPC. Edge Functions own HTTP: real HMAC-SHA512 verification, settlement invoked after verification (never pre-marking PAID), checkout verifies caller JWT + ownership + state and reuses payments idempotently. Mobile switches checkout from the broken PostgREST `rpc('paymob-checkout')` to Edge Function transport. Fresh migration chain + source-of-truth docs fixed last.

**Tech Stack:** Supabase (PostgreSQL 17 local, RLS, PostgREST, pg_cron), Deno 2 Edge Functions (`crypto.subtle`), Flutter mobile (`supabase_flutter` functions.invoke), psql regression tests, GitHub Actions CI.

**Depends on:** `docs/superpowers/plans/2026-08-05-church-digital-platform.md` (master, decisions A1–A12), `docs/superpowers/plans/conventions.md`.

---

## Decisions locked 2026-08-10 (user)

| # | Question | Decision |
|---|----------|----------|
| D1 | Plan scope | **Critical blockers only.** Deepening candidates (payment settlement module, domain adapters, composition, design system, outbox claim, slot allocation, authorization module) deferred to later plans. |
| D2 | `apps/admin` (39 uncommitted deletions, CI fails) | **Restore from HEAD** (Task 1). |
| D3 | Postgres version drift (config `17` vs docs `16`) | **Keep 17; update docs** (Task 12). |
| D4 | YouTube expiry (A2 says never PRIVATE; code flips PRIVATE) | **Keep UNLISTED; change code** — expiry blocks new purchases in SQL, function deleted (Task 6). |

## Environment prerequisites (verify before Task 2)

- **Docker Desktop installed and running** — the 2026-08-10 review could not run the SQL suite ("Docker/Podman not installed on PATH"). Without it, `npx supabase start` and every SQL verification step fail. Install Docker first.
- Local stack: `npx supabase start` (from repo root; CLI is an npm devDependency).
- `deno` v2.x on PATH (edge-function tests).
- Flutter stable on PATH (mobile tests; run from `apps/mobile`).
- psql on PATH (SQL tests).

## Review-findings → task mapping

| Review finding | Severity | Task |
|---|---|---|
| Fresh migration chain broken (0002 uses `is_admin()` defined in 0025; 0027 references missing `refund_requests`) | CRITICAL | 2 |
| Transition engine client-callable; privileged SQL callable by default; NULL ownership bypass in `cancel_booking`/`transition_booking_status` | CRITICAL | 3 |
| Webhook plain SHA-512 instead of HMAC-SHA512 | CRITICAL | 8 |
| Webhook marks PAID before settlement → booking/video never settle; REFUNDED replay regresses to REFUND_PENDING | CRITICAL | 3, 8 |
| Checkout trusts caller IDs (no JWT/ownership/state/idempotency) | CRITICAL | 9 |
| Mobile transport broken (`rpc('paymob-checkout')` — no such SQL function) | CRITICAL | 11 |
| Admin role can self-escalate; broad `FOR ALL` policies lack tenant predicate | CRITICAL | 4 |
| Complaint priest can self-assign; broad admin policy beats deny policy | CRITICAL | 4 |
| Known complaint key provisioned by migration | CRITICAL | 5 |
| Analytics-export role lookup uses anon client without caller JWT → no row → 403 for everyone | FAIL (matrix) | 10 |
| YouTube expiry flips PRIVATE (conflicts with A2) | PLAN CONFLICT | 6, 12 |
| Deno suite fails before tests (`Deno.serve` at import) | Validation | 7 |
| `apps/admin` deletions break CI | SCOPE BLOCKER | 1 |
| Source-of-truth drift (master/conventions/GEMINI mention `whatsapp_outbox`, `refund_requests`, PG 16, `whatsapp-sender`); historical plans executable-looking | SCOPE BLOCKER | 12 |

**Deferred (documented, not implemented):** candidates from both reviews — deep payment settlement module, domain adapters, navigation/session composition, design-system interaction semantics, outbox claim, slot allocation, authorization module.

---

### Task 1: Restore apps/admin + CI from HEAD

**Files:**
- Restore: `apps/admin/**` (all 39 deleted files)
- Restore: `.github/workflows/ci.yml`, `.github/workflows/.gitkeep`, `.github/copilot-instructions.md`

**Context:** The worktree contains 39 uncommitted deletions under `apps/admin` plus deleted CI files. Decision D2: restore them. Nothing else is touched (`.gitignore`, `GEMINI.md`, `skills-lock.json`, `supabase/functions/event-dispatcher/index.ts`, `supabase/functions/paymob-checkout/index.ts`, `supabase/functions/youtube-expiry/index_test.ts`, `supabase/migrations/0008_booking_state_machine.sql` stay modified as-is — in-progress user changes).

- [ ] **Step 1: Inspect current status**

Run:
```powershell
git status --short | Select-String -Pattern '^ D'
```
Expected: the `apps/admin/**`, `.github/workflows/ci.yml`, `.github/workflows/.gitkeep`, `.github/copilot-instructions.md` deletions (and no other deleted paths).

- [ ] **Step 2: Restore deleted paths only**

Run:
```powershell
git checkout HEAD -- apps/admin .github/workflows .github/copilot-instructions.md
git status --short | Select-String -Pattern '^ D'
```
Expected: no remaining `^ D` lines.

- [ ] **Step 3: Verify CI references admin again**

Run:
```powershell
Select-String -Path .github/workflows/ci.yml -Pattern 'flutter-admin|apps/admin'
```
Expected: `flutter-admin:` job with `working-directory: apps/admin` present.

- [ ] **Step 4: Commit**

```bash
git add apps/admin .github/workflows .github/copilot-instructions.md
git commit -m "chore: restore apps/admin and CI from HEAD (release-blocker scope)"
```

---

### Task 2: Fix fresh migration chain

**Files:**
- Modify: `supabase/migrations/0002_rls_baseline.sql` (define role helpers before first use)
- Modify: `supabase/migrations/0027_event_outbox.sql` (guard missing legacy table)
- Test: `npx supabase db reset` + `supabase/tests/run_all.sql` (existing suite)

**Context:** On a fresh `supabase db reset`, `0002` creates `p0_admin_all` policies whose `using (public.is_admin())` fails because `is_admin()` is only defined in `0025`. `0005`/`0008` similarly use `is_admin_or_priest()` before 0025. `0027` selects `from public.refund_requests`, a table no migration creates. Fix by defining the three helpers at the top of 0002 (0025 later re-`create or replace`s them — harmless) and guarding the legacy-table selects in 0027.

- [ ] **Step 1: Prove the chain is broken**

Run:
```powershell
npx supabase start
npx supabase db reset
```
Expected: FAIL — `ERROR: function public.is_admin() does not exist` (during 0002 policy creation) or `ERROR: relation "public.refund_requests" does not exist` (during 0027). Record the exact error.

- [ ] **Step 2: Define role helpers in 0002**

Edit `supabase/migrations/0002_rls_baseline.sql`. Immediately after the `current_user_role()` function block (after line 24), insert:

```sql
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.current_user_role() in ('ADMIN','SUPER_ADMIN')
$$;

create or replace function public.is_admin_or_priest()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.current_user_role() in ('ADMIN','PRIEST','SUPER_ADMIN')
$$;

create or replace function public.is_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.current_user_role() = 'SUPER_ADMIN'
$$;
```

- [ ] **Step 3: Re-run reset, expect next failure**

Run:
```powershell
npx supabase db reset
```
Expected: migrations now pass 0002–0026; FAIL at 0027 with `relation "public.refund_requests" does not exist`.

- [ ] **Step 4: Guard legacy-table references in 0027**

Edit `supabase/migrations/0027_event_outbox.sql`. Replace the two raw legacy-table selects (lines 25–34) with:

```sql
-- migrate queued rows (deployed DBs; fresh resets start empty)
insert into public.event_outbox (tenant_id, handler_type, payload, status, attempts, next_attempt_at, created_at)
select coalesce(o.tenant_id, 1), 'WHATSAPP',
       jsonb_build_object('phone', o.phone, 'template_name', o.template_name, 'params', o.params),
       o.status::text::public.outbox_status, o.attempts, o.next_attempt_at, o.created_at
from public.whatsapp_outbox o;
do $$
begin
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'refund_requests') then
    insert into public.event_outbox (tenant_id, handler_type, payload, status, attempts, next_attempt_at, created_at)
    select 1, 'PAYMOB_REFUND',
           jsonb_build_object('payment_id', r.payment_id, 'amount', r.amount),
           'PENDING', r.attempts, r.next_attempt_at, r.created_at
    from public.refund_requests r;
  end if;
end $$;
```

- [ ] **Step 5: Re-run reset, expect PASS**

Run:
```powershell
npx supabase db reset
```
Expected: all 26 migrations apply, seed.sql runs, exit 0.

- [ ] **Step 6: Run full SQL regression suite**

Run:
```powershell
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/run_all.sql
```
Expected: no output, exit 0 (all 24 existing test files pass on the fixed chain).

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/0002_rls_baseline.sql supabase/migrations/0027_event_outbox.sql
git commit -m "fix(migrations): define role helpers before first use; guard missing refund_requests"
```

<!-- CHUNK2 -->
