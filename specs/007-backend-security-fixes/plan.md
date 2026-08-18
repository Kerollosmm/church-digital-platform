# Implementation Plan: Backend Security and Correctness Fixes

**Branch**: `007-backend-security-fixes` | **Date**: 2026-08-17 (revised after live-database verification) | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/007-backend-security-fixes/spec.md`, derived from the 2026-08-17 backend audit, the 007/008 planning handoff, and **direct inspection of the running `supabase_db_church` database**.

> Every signature, column, policy, and grant referenced below was verified live. The audit prose and
> the first draft of this plan contained several names that do not exist in the schema
> (`expires_at`, `gateway_order_id`, `raw_payload`, `start_time`, `retry_count`, `error_message`,
> `fn_decrement_slot_capacity`). Do not reintroduce them — a `REVOKE` or `ALTER` naming a
> non-existent object aborts the entire migration.

---

## Summary

This feature closes the privilege and concurrency holes found in the 2026-08-17 audit: it establishes
an RPC-only write boundary on the five sensitive tables, hardens the `SECURITY DEFINER` functions
still left at PostgreSQL's default `EXECUTE TO PUBLIC`, adds inbound authentication to the two
cron-driven edge functions, deletes the drifting slot counter, adds crash recovery to the outbox,
restores a usable `SUPER_ADMIN`, makes payment reconciliation resilient to gateway blips, and removes
the cancelled personal-video feature end to end.

Key deliverables:

1. **Two forward migrations** — the split is mandatory, not stylistic (see §Technical Context):
   - `0052_super_admin_role.sql` — `ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'SUPER_ADMIN';`
     and nothing else.
   - `0053_backend_security_and_correctness_fixes.sql` — everything else:
     - `REVOKE INSERT, UPDATE, DELETE` from `anon`/`authenticated` on `payments`, `complaints`,
       `users`, `audit_log`, `roles_permissions`; drop `p0_admin_all` from the four tables that carry
       it **and create replacement admin `SELECT` policies in the same migration**, because
       `p0_admin_all` is the only policy on `payments`, `audit_log`, and `roles_permissions`.
     - Harden `apply_payment(bigint)`, `expire_stale_bookings()`, `promote_waiting_list(bigint)`,
       `materialize_analytics()`, and `rbac_allows(app_role, text, text)`.
     - Drop `service_slots.remaining_capacity` **and its three writers**; leave `v_available_slots`
       untouched — it already derives availability dynamically with `security_invoker=true`.
     - Consolidate the two `book_slot` overloads into
       `book_slot(bigint, boolean DEFAULT false, uuid DEFAULT NULL)`.
     - Decommission `videos`/`video_purchases`, drop `payments.video_id`, remove `video_ready` from
       `event_outbox_whatsapp_template_check`, and **unschedule the live `youtube-expiry` pg_cron job**.
     - Add `event_outbox.claimed_at` and `event_outbox.last_error`; update
       `claim_event_outbox_batch` to stamp `claimed_at`; add `reap_stuck_outbox_events(interval)`,
       `v_failed_outbox_events`, and `admin_resend_outbox_event(bigint)`.
     - Update `is_super_admin()` to compare against the new enum label; purge dead `PRIEST` references.
     - Re-apply idempotently the 0043/0044 changes that were edited in place on `main` and therefore
       never reached `supabase db push` environments.
     - Fix the `v_content_backlog` `priests` branch (external URLs are permanent false positives).
2. **Edge function updates**:
   - `reconcile-payments`: inbound bearer authentication; log-and-`continue` on transient non-2xx
     instead of calling `mark_payment_failed`.
   - `event-dispatcher`: inbound bearer authentication; write `last_error` on failure; drop the
     `video_ready` handler.
   - `paymob-checkout`: module-scope fail-fast validation of the four Paymob secrets.
   - Delete `youtube-expiry/` and `deliver-personal-video/`.
3. **Client cleanup** — **both apps**: mobile (`features/video/`, `repositories/videos_repository.dart`,
   router, hub, nav scaffold, strings, error mapper, six tests) and admin
   (`features/videos/videos_admin_screen.dart`, which performs `from('videos').insert(...)`, plus its
   test and the admin router).
4. **Tests & tooling**: two new suites registered in `run_all.sql`; **nine existing suites updated**
   where they reference `remaining_capacity`; minimal root `package.json` so the e2e script can run.
5. **Documentation**: two `AGENTS.md` invariant amendments (`PRIEST`, and grant-level denial
   semantics), plus explicit recording of the `tenant_id()` single-tenant scaffolding.

---

## Technical Context

**Language/Version**: SQL (PostgreSQL 16 via Supabase) + TypeScript on Deno (edge functions);
Dart/Flutter for the client cleanup.

**Why two migrations.** `ALTER TYPE ... ADD VALUE` may run inside a transaction on PostgreSQL 12+,
but the newly added label **cannot be referenced in that same transaction**
(`55P04 unsafe_new_enum_value_usage`). Supabase applies each migration file in one transaction, so a
single file that adds `SUPER_ADMIN` and then compares against it in `is_super_admin()` fails at apply
time. There is no prior `ALTER TYPE` anywhere in `supabase/migrations/`, so this path is untested in
this repo and should be verified against a fresh `supabase db reset` before merge.

**Primary Dependencies**:
- Installed PostgreSQL extensions: `pgcrypto`, `pg_cron`, `pg_net`, `supabase_vault`.
- **`dblink` is available but NOT installed.** The concurrency suite runs
  `CREATE EXTENSION IF NOT EXISTS dblink;` itself (test scripts execute as `postgres`). `EXECUTE` on
  `dblink` functions must stay restricted to `postgres` — it is a privileged outbound-connection
  primitive and must never be granted to `anon` or `authenticated`.
- **`pg_background` is not available at all** in this image; it cannot be used for multi-session tests.
- Deno shared modules: `_shared/http.ts`, `_shared/paymob.ts`, `_shared/messages.ts`.
- Node.js with `@supabase/supabase-js` for `supabase/e2e/book_pay_flow.mjs`.

**Storage**: Supabase PostgreSQL — migrations `0052_super_admin_role.sql` and
`0053_backend_security_and_correctness_fixes.sql`.

**Testing**:
- New suites use pgTAP (handoff decision 13). The 42 pre-existing suites stay in their plain-assert
  style — but that exemption is about *style*, not about compiling: nine of them reference columns
  this feature drops and must be updated.
- `supabase/tests/0053_security_fixes_test.sql` — negative authorization, outbox reaper, role
  validation, `v_available_slots` column-contract regression.
- `supabase/tests/0053_concurrency_test.sql` — genuine multi-session races over `dblink`.
- Suites are executed over **stdin**, not `-f`: `/tests` is not mounted inside `supabase_db_church`.
- `deno test --allow-env supabase/functions/` for edge-function units.
- `node supabase/e2e/book_pay_flow.mjs` for the end-to-end flow (requires staging Paymob and `TEST_*`
  secrets supplied out of band; never committed).

**Target Platform**: Supabase backend — local Docker (`supabase_db_church`,
`supabase_edge_runtime_church`) and the production cloud instance.

**Project Type**: Backend security and correctness; includes client deletions for the product pivot.

**Performance Goals**:
- `v_available_slots` continues to serve the slot grid; `active_booking_count` is already indexed on
  `bookings(slot_id, status)`.
- `reap_stuck_outbox_events` completes well inside its 5-minute cron window using
  `FOR UPDATE SKIP LOCKED` so it never blocks the dispatcher.
- Grant revocation adds no runtime cost; it removes a code path rather than adding one.

**Constraints**:
- Forward-only migrations; no edits to already-numbered files. (007 also *repairs* the consequences of
  eleven past violations of this rule — see research R10.)
- Zero plaintext credentials or fallbacks in code.
- The frozen Arabic error-code contract is not extended: no new error codes.
- Money stays in integer piastres (1 EGP = 100).
- `GRANT ALL` is never used; grants are granular.
- No `CREATE INDEX CONCURRENTLY` inside migration files.
- The Paymob webhook remains the only authority that marks an online payment paid; the client never
  writes payment status.

**Scale/Scope**:
- 2 forward migrations.
- 2 new SQL test suites; **9 existing suites to update** (`0007`, `0008`, `0009`, `0010`, `0012`,
  `0021`, `0035`, `0037`, `0047`).
- 3 edge functions updated (`reconcile-payments`, `event-dispatcher`, `paymob-checkout`);
  2 deleted (`youtube-expiry`, `deliver-personal-video`).
- 2 Flutter apps touched for the video removal (mobile **and** admin).
- 1 pg_cron job unscheduled (jobid 4, `youtube-expiry`); 1 added (the reaper).
- 1 minimal root `package.json`.
- 2 `AGENTS.md` invariant amendments.

---

## Constitution Check

*GATE: verified against `.specify/memory/constitution.md` and `AGENTS.md`. Two genuine conflicts are
recorded rather than papered over.*

| Core Principle / Locked Decision | Compliance Analysis | Status |
|---|---|---|
| **I. Test-First** | Red-first suites precede implementation for US1 (negative authorization), US2 (concurrency + view contract), US4 (reaper/resend), US6 (Deno transient-error cases). **Partial:** US3 (video removal) is a deletion — its verification is an absence assertion written alongside, not before, the drop; US5's role assertions cannot be written before `0052` adds the enum label, because a test referencing `'SUPER_ADMIN'` will not parse until then. Both exceptions are deliberate and scoped. | ⚠️ PASS WITH NOTED EXCEPTIONS |
| **II. Security by Default** | Direct DML revoked on the five sensitive tables with replacement admin `SELECT` policies created in the same migration; five PUBLIC-executable `SECURITY DEFINER` functions narrowed; inbound authentication added to the two cron-driven edge functions; `dblink` `EXECUTE` withheld from `anon`/`authenticated`. | ✅ PASS |
| **III. Forward-Only Migrations** | All changes land in new files `0052` and `0053`; no already-numbered file is edited. 0053 additionally re-applies, idempotently, the 0043/0044 changes that a previous in-place edit left with no forward path. | ✅ PASS |
| **IV. Arabic-First** | Arabic error contract preserved unchanged; the new `401` on the cron endpoints reuses the existing frozen `UNAUTHORIZED` body. No new error codes. | ✅ PASS |
| **V. Deep Modules, Thin Handlers** | Reconciliation classification logic stays in the function body behind the existing gateway adapter; handlers remain thin. | ✅ PASS |
| **RPC Money Boundaries** | `payments` DML revoked from clients entirely; status transitions remain confined to `apply_payment`, `mark_payment_failed`, `mark_payment_refunded`, all now service-role only. | ✅ PASS |
| **Role Verification Invariant** | Role checks continue to read `users.role` with the service client. `SUPER_ADMIN` becomes reachable; dead `PRIEST` purged. **Requires amending `AGENTS.md:31`**, which hardcodes `ADMIN\|PRIEST\|SUPER_ADMIN` as the admin-route invariant. | ⚠️ PASS — invariant text must change with the code |
| **Slot Locking Invariant** | Canonical `book_slot` takes `SELECT capacity ... FOR UPDATE` on the slot row before testing `active_booking_count` in the same transaction; `expire_stale_bookings` selects candidates `FOR UPDATE SKIP LOCKED`. | ✅ PASS |
| **`AGENTS.md:33` — unauthorized `UPDATE`/`DELETE` must assert 0 rows affected, not exceptions** | Correct for RLS-level denial, and 007 keeps it there. But table-level `REVOKE` raises `42501 insufficient_privilege`; an exception is the only observable outcome, so 007's negative-authorization tests would violate the invariant as written. **The invariant needs an explicit carve-out for grant-level denial.** | ❌ CONFLICT — resolve by amending `AGENTS.md` in this feature |

Both flagged rows are documentation amendments carried as tasks in this feature, not deviations left
outstanding.

---

## Project Structure

### Documentation (this feature)

```text
specs/007-backend-security-fixes/
├── plan.md              # This file
├── spec.md              # Requirements and acceptance criteria
├── research.md          # R1–R10 decisions, with live-verification corrections
├── data-model.md        # Verified schema, privilege table, state machines
├── quickstart.md        # Verification gates (bash; stdin psql)
├── contracts/
│   ├── database-rpc-contracts.md    # Exact live signatures, privileges, errors
│   └── edge-functions-contracts.md  # [CURRENT] vs [TO BUILD] per behaviour
├── checklists/
│   └── requirements.md  # Verification record
└── tasks.md             # Ordered task list
```

### Source Code (repository root)

```text
supabase/
├── migrations/
│   ├── 0052_super_admin_role.sql                          # ALTER TYPE only — separate transaction
│   └── 0053_backend_security_and_correctness_fixes.sql     # Everything else
├── tests/
│   ├── 0053_security_fixes_test.sql                        # pgTAP: negative auth, reaper, roles, view contract
│   ├── 0053_concurrency_test.sql                           # pgTAP + dblink: real multi-session races
│   ├── run_all.sql                                         # Register both new suites
│   └── 0007|0008|0009|0010|0012|0021|0035|0037|0047_*.sql  # Update remaining_capacity references
└── functions/
    ├── reconcile-payments/
    │   ├── index.ts            # Inbound auth; log & continue on transient non-2xx
    │   └── index_test.ts       # 502 / timeout / terminal-decline cases
    ├── event-dispatcher/
    │   └── index.ts            # Inbound auth; write last_error; drop video_ready handler
    ├── paymob-checkout/
    │   └── index.ts            # Module-scope secret fail-fast
    ├── youtube-expiry/         # [DELETED — product pivot; its pg_cron job is unscheduled in 0053]
    └── deliver-personal-video/ # [DELETED — product pivot; untracked, never shipped]

apps/mobile/lib/
├── features/video/             # [DELETED]  (directory is singular)
├── repositories/videos_repository.dart   # [DELETED]  (filename is plural)
├── app_router.dart             # Remove video route
├── features/home/home_hub_screen.dart, bottom_nav_scaffold.dart  # Remove entry points
└── services/app_strings.dart, services/error_mapper.dart          # Remove video strings/codes

apps/admin/lib/
├── features/videos/videos_admin_screen.dart   # [DELETED] — performs from('videos').insert(...)
└── app_router.dart                            # Remove video route

AGENTS.md                       # PRIEST purge; grant-level-denial test carve-out; storage-object RLS note
package.json                    # Minimal root config declaring @supabase/supabase-js
```

---

## Complexity Tracking

| Item | Why it is not avoidable | Alternative rejected |
|---|---|---|
| Two migrations instead of one | PostgreSQL forbids referencing a newly added enum label in the same transaction (`55P04`), and Supabase wraps each file in one transaction | Single file — fails at apply time |
| Replacement `SELECT` policies alongside the `p0_admin_all` drop | `p0_admin_all` is the only policy on `payments`, `audit_log`, `roles_permissions`; dropping it alone silently returns zero rows to admins | Drop-only — breaks the admin payments screen |
| Moving the `SLOT_EXHAUSTED` `pg_notify` into `book_slot` | The signal currently comes from a trigger on the `remaining_capacity` 1→0 edge; that column is being dropped | Lose the realtime signal |
| 0053 re-applying 0043/0044 changes | Those files were edited in place on `main`, so `supabase db push` environments never received them | Leave environments divergent |
