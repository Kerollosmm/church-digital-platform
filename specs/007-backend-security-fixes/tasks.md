# Tasks: Backend Security and Correctness Fixes

**Input**: Design documents from `/specs/007-backend-security-fixes/`  
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`  
**Tests**: Mandatory per Constitution Principle I. Two deliberate exceptions are recorded in
`plan.md`'s Constitution Check (US3 is a deletion; US5's role assertions cannot parse before the enum
label exists).  
**Organization**: grouped by user story.

> **Migration numbering.** There are **two** migrations, and the split is mandatory:
> `0052_super_admin_role.sql` contains the `ALTER TYPE` and nothing else, because a newly added enum
> label cannot be referenced in the transaction that adds it (`55P04`) and Supabase wraps each file in
> one transaction. Everything else lands in `0053_backend_security_and_correctness_fixes.sql`.
>
> **`[P]` and the shared migration file.** Almost every SQL task edits
> `0053_backend_security_and_correctness_fixes.sql`. Those tasks are **not** parallelisable — `[P]`
> appears only where the files genuinely differ.
>
> **Every signature, column, policy, and path below was verified against the live database and working
> tree on 2026-08-17.** Do not substitute names from the audit prose.

---

## Phase 1: Setup

- [x] T001 [P] Create minimal root `package.json` declaring only `@supabase/supabase-js`, so
  `node supabase/e2e/book_pay_flow.mjs` resolves its import
- [x] T002 [P] Amend `AGENTS.md` invariant on unauthorized-write tests: add an explicit carve-out that
  **grant-level** denial (`REVOKE`) is asserted as a `42501 insufficient_privilege` exception, while the
  existing "assert 0 rows affected, not exceptions" rule continues to govern **RLS-level** denial.
  Without this, US1's own tests violate the constitution they are checked against — so it blocks T009.

---

## Phase 2: Foundational (Blocking Prerequisites)

- [x] T003 Create `supabase/migrations/0052_super_admin_role.sql` containing exactly
  `ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'SUPER_ADMIN';` and no other statement
- [x] T004 Create scaffold `supabase/migrations/0053_backend_security_and_correctness_fixes.sql`
  (header comment, ordered section markers matching the phases below)
- [x] T005 [P] Create pgTAP suite scaffold `supabase/tests/0053_security_fixes_test.sql`
- [x] T006 [P] Create pgTAP concurrency scaffold `supabase/tests/0053_concurrency_test.sql` beginning
  with `CREATE EXTENSION IF NOT EXISTS dblink;` — `dblink` is available but **not installed**, and
  `pg_background` is unavailable in this image. Do **not** grant `EXECUTE` on any `dblink` function to
  `anon` or `authenticated`
- [x] T007 Register both new suites in `supabase/tests/run_all.sql` (file has CRLF endings — preserve them)
- [x] T008 Verify `npx supabase db reset` applies `0052` then the `0053` scaffold with no `55P04`

**Checkpoint**: foundation ready.

---

## Phase 3: User Story 1 — Tamper-Proof Financial & Audit Operations (P1) 🎯 MVP

**Goal**: revoke client DML on `payments`, `complaints`, `users`, `audit_log`, `roles_permissions`;
replace the policies that drop would otherwise remove; harden the five PUBLIC-executable
`SECURITY DEFINER` routines.

**Independent Test**: direct DML as `authenticated`/`anon` and RPC calls as `anon` are refused with
`42501`; admin `SELECT` on all five tables still returns rows.

### Tests for User Story 1 (write FIRST, ensure they FAIL) ⚠️
- [x] T009 [US1] In `supabase/tests/0053_security_fixes_test.sql`, add failing assertions for:
  `INSERT/UPDATE/DELETE` refused as `authenticated` **and** as `anon` on all five tables;
  `apply_payment(1)` refused as `anon`; `rbac_allows('ADMIN','payments','update')` refused as `anon`;
  `expire_stale_bookings()`, `promote_waiting_list(1)`, `materialize_analytics()` refused as
  `authenticated`. Assert on `42501` per the T002 carve-out
- [x] T010 [US1] Add failing positive-read assertions: admin `SELECT` returns rows from `payments`,
  `audit_log`, `roles_permissions`, and `v_complaints` — these guard against the policy-drop regression

### Implementation for User Story 1
- [x] T011 [US1] `REVOKE INSERT, UPDATE, DELETE ON public.payments, public.complaints,
  public.audit_log, public.roles_permissions FROM anon, authenticated;` and the same for
  `public.users`. **Retain `SELECT`.** In `0053`
- [x] T012 [US1] Drop `p0_admin_all` from `payments`, `complaints`, `audit_log`, `roles_permissions`
  **and create replacement policies in the same statement block** — `payments_admin_select`
  (`is_admin() AND tenant_id = public.tenant_id()`), `audit_log_admin_select` and
  `roles_permissions_admin_select` (`is_admin()` only — **neither table has a `tenant_id` column**).
  `complaints` needs no replacement: its restrictive `complaints deny table access` policy starts
  working once the permissive `p0_admin_all` stops OR-ing with it, and the admin list reads
  `v_complaints`. **`users` has no `p0_admin_all`** — it uses granular
  `p0_admin_{read,insert,update,delete}_users`; do not attempt to drop a policy that does not exist. In `0053`
- [x] T013 [US1] Drop the now-unreachable `complaints_admin_assign` UPDATE policy, and record that any
  future complaint assignment must go through an RPC. In `0053`
- [x] T014 [US1] `REVOKE ALL ON FUNCTION public.apply_payment(bigint) FROM PUBLIC, anon, authenticated;
  GRANT EXECUTE ... TO service_role;` — the signature is **one `bigint` argument**. The three-argument
  `(bigint, text, jsonb)` form named in the audit does not exist and would abort the migration. In `0053`
- [x] T015 [US1] Restrict `expire_stale_bookings()`, `promote_waiting_list(bigint)`, and
  `materialize_analytics()` to `service_role, postgres` (`postgres` is required — pg_cron runs as it). In `0053`
- [x] T016 [US1] `REVOKE ALL ON FUNCTION public.rbac_allows(public.app_role, text, text)
  FROM PUBLIC, anon;` — unguarded, PUBLIC-executable, and with **no caller** in any routine or policy,
  it lets anon enumerate the RBAC matrix. In `0053`
- [x] T017 [US1] Confirm **no change** is made to `active_booking_count` (read-only; `v_available_slots`
  depends on it) or to the seven internally guarded routines (`decrypt_complaint`,
  `emergency_override`, `cancel_booking`, `confirm_booking`, `complete_booking`, `join_waiting_list`,
  `manual_book`). Record the decision as a migration comment
- [x] T018 [US1] Verify T009 and T010 pass (Green)
- [x] T019 [US1] Manually verify `apps/admin/lib/features/payments/payments_admin_screen.dart:15` still
  loads, and sweep `apps/admin/lib` and `apps/mobile/lib` confirming no `insert`/`update`/`delete`
  against the five tables was silently broken

**Checkpoint**: financial state and audit trail are tamper-proof, and admin reads still work.

---

## Phase 4: User Story 2 — Accurate Slot Capacity Without Counter Drift (P1)

**Goal**: delete `service_slots.remaining_capacity` and its three writers; consolidate `book_slot`;
add expiry-sweep locking. **`v_available_slots` is NOT rewritten** — it already derives dynamically
with `security_invoker=true` and a tenant predicate.

**Independent Test**: two simultaneous bookings on a one-seat slot → exactly one succeeds; the view's
column list is unchanged; no object references the dropped column.

### Tests for User Story 2 (write FIRST, ensure they FAIL) ⚠️
- [x] T020 [P] [US2] In `0053_security_fixes_test.sql`, add a **regression test pinning the
  `v_available_slots` column contract**: `slot_id, service_id, title_ar, starts_at, ends_at, capacity,
  price, location, booked_count, available_seats, slot_status`. Six Dart files and five widget tests
  depend on these exact names
- [x] T021 [P] [US2] In `0053_concurrency_test.sql`, add failing multi-session tests over `dblink`:
  (a) two simultaneous `book_slot` calls on a slot with one seat left → one succeeds, one raises
  `SLOT_FULL`; (b) `apply_payment` racing `expire_stale_bookings` on the same booking → the settled
  booking is skipped, not cancelled
- [x] T022 [P] [US2] Add a failing assertion that the `SLOT_EXHAUSTED` `pg_notify` payload is still
  emitted when the last seat is taken, so the realtime signal survives the trigger's removal

### Implementation for User Story 2
- [x] T023 [US2] Drop trigger `tr_restore_slot_capacity` on `bookings`, then function
  `fn_restore_slot_capacity_on_cancel`. In `0053`
- [x] T024 [US2] Drop trigger `tr_on_slot_depletion` on `service_slots`, then function
  `fn_broadcast_slot_depletion`. It is uncompilable once the column is gone. In `0053`
- [x] T025 [US2] Create the canonical
  `public.book_slot(p_slot_id bigint, p_opt_in boolean DEFAULT false, p_idempotency_key uuid DEFAULT NULL) RETURNS public.bookings`,
  after dropping **both** existing overloads (`(bigint, boolean)` from 0048 and
  `(bigint, integer, boolean, uuid)` from 0039) and the helper `fn_book_slot_atomic`. It must
  `SELECT capacity FROM public.service_slots WHERE id = p_slot_id AND deleted_at IS NULL FOR UPDATE`
  before comparing against `active_booking_count(p_slot_id)`, and emit the `SLOT_EXHAUSTED` `pg_notify`
  payload when the post-insert count reaches `capacity`. **`p_opt_in` must keep its name** — it is the
  WhatsApp opt-in flag, passed by name from
  `apps/mobile/lib/repositories/supabase_booking_repository.dart:55` and asserted in
  `apps/mobile/test/features/booking/booking_flow_test.dart:55`. `p_quantity` is not carried over
  (`bookings.seat_count` is fixed at 1). Then
  `REVOKE ALL ... FROM PUBLIC, anon; GRANT EXECUTE ... TO authenticated;`. In `0053`
- [x] T026 [US2] Re-verify `manual_book` against the new `book_slot` signature — it is the other
  in-database caller. In `0053`
- [x] T027 [US2] `ALTER TABLE public.service_slots DROP COLUMN remaining_capacity;` — only after
  T023–T026. In `0053`
- [x] T028 [US2] Add `FOR UPDATE SKIP LOCKED` to the candidate select inside `expire_stale_bookings`:
  `WHERE status = 'PENDING_PAYMENT' AND locked_until < now()`. The deadline column is **`locked_until`**
  — there is no `bookings.expires_at`. Preserve the existing
  `transition_booking_status(r.id, 'CANCELLED', 'expire_lock', ...)` and `promote_waiting_list(r.slot_id)`
  calls; the booking status enum has **no `EXPIRED`** label. In `0053`
- [x] T029 [US2] Audit and update the **nine existing suites** that reference `remaining_capacity`,
  `available_seats`, or `slot_status`: `supabase/tests/0007_*`, `0008_*`, `0009_*`, `0010_*`, `0012_*`,
  `0021_*`, `0035_*`, `0037_*`, `0047_*`. They keep their plain-assert style (handoff decision 13) but
  must still compile
- [x] T030 [US2] Verify T020–T022 pass (Green) and the full SQL suite still passes

**Checkpoint**: one source of truth for capacity; races proven serialised.

---

## Phase 5: User Story 3 — Clean Pivot & Decommissioning of Video Machinery (P2)

**Goal**: zero video footprint in the database, the edge runtime, the scheduler, and **both** Flutter
apps.

**Note on test-first**: this story is a deletion. Its verification is an absence assertion written
alongside the drops (T037), not before them — recorded as a deliberate exception in `plan.md`.

### Implementation for User Story 3
- [x] T031 [US3] `DROP TABLE IF EXISTS public.video_purchases CASCADE;` then
  `DROP TABLE IF EXISTS public.videos CASCADE;` (both verified 0 rows) and
  `ALTER TABLE public.payments DROP COLUMN IF EXISTS video_id;`. In `0053`
- [x] T032 [US3] Drop `purchase_video(bigint, uuid)`, `apply_video_payment(bigint)`, and
  `deliver_personal_video(text, text, text, bigint)`. In `0053`
- [x] T033 [US3] Drop and recreate `event_outbox_whatsapp_template_check` **without** `video_ready`.
  The verified remaining allow-list is `booking_confirmed, payment_received, booking_cancelled,
  booking_rescheduled, booking_apology, otp_auth, booking_payment_received, booking_offer`. There is
  **no `payment_receipt` template** — do not add one. In `0053`
- [x] T034 [US3] **Unschedule the live `youtube-expiry` pg_cron job** (jobid 4, `0 4 * * *`, POSTs to
  `/functions/v1/youtube-expiry`). Use a guarded `cron.unschedule` lookup by command pattern so the
  statement is idempotent. In `0053`
- [x] T035 [P] [US3] Delete `supabase/functions/youtube-expiry/` and
  `supabase/functions/deliver-personal-video/` (the latter is untracked — added by feature 004, never
  shipped)
- [x] T036 [P] [US3] Remove the `video_ready` handler from `supabase/functions/event-dispatcher/index.ts`
- [x] T037 [US3] Add absence assertions to `0053_security_fixes_test.sql`: 0 rows for the two tables,
  `payments.video_id`, and the three routines
- [x] T038 [P] [US3] **Mobile** cleanup — delete `apps/mobile/lib/features/video/` (directory is
  **singular**) and `apps/mobile/lib/repositories/videos_repository.dart` (filename is **plural**);
  remove references in `app_router.dart`, `home_hub_screen.dart`, `bottom_nav_scaffold.dart`,
  `services/app_strings.dart`, `services/error_mapper.dart`; update the six affected test files
  including `apps/mobile/test/helpers/fakes.dart`
- [x] T039 [P] [US3] **Admin** cleanup — delete `apps/admin/lib/features/videos/videos_admin_screen.dart`
  (it performs `from('videos').insert(...)` and would fail at runtime once the table is dropped) and
  `apps/admin/test/features/videos/videos_admin_screen_test.dart`; remove the route from
  `apps/admin/lib/app_router.dart`
- [x] T040 [US3] `flutter analyze` and `flutter test` clean in **both** apps

**Checkpoint**: no residual video footprint anywhere.

---

## Phase 6: User Story 4 — Resilient Background Dispatch & Processing Recovery (P2)

**Goal**: schema, reaper, admin read surface, and resend RPC for the outbox.

**Independent Test**: a row stranded in `PROCESSING` past the timeout is recovered; one already at 5
attempts is parked rather than incremented; resend is admin-only.

### Tests for User Story 4 (write FIRST, ensure they FAIL) ⚠️
- [x] T041 [US4] In `0053_security_fixes_test.sql`, add failing assertions for: reaper returns a
  timed-out row to `PENDING` with `attempts + 1`, `next_attempt_at = now()`, `claimed_at = NULL`;
  reaper parks an `attempts = 5` row as `FAILED` with `last_error` set **without raising** (an
  unconditional increment violates `event_outbox_attempts_check`, `attempts >= 0 AND attempts <= 5`,
  and would abort the whole run); `admin_resend_outbox_event` resets a row for an admin and raises
  `FORBIDDEN` for a non-admin and `EVENT_NOT_FOUND` for an unknown id; `v_failed_outbox_events` returns
  nothing to a non-admin
- [x] T042 [P] [US4] In `0053_concurrency_test.sql`, add a failing test that concurrent
  `claim_event_outbox_batch` calls over `dblink` never return the same row twice

### Implementation for User Story 4
- [x] T043 [US4] `ALTER TABLE public.event_outbox ADD COLUMN claimed_at timestamptz, ADD COLUMN
  last_error text;`. The current table is exactly `id, tenant_id, handler_type, payload, status,
  attempts, next_attempt_at, created_at` — there is no `updated_at`, `locked_until`, `retry_count`, or
  `error_message`, so the reaper cannot be built without this. In `0053`
- [x] T044 [US4] Update `claim_event_outbox_batch(integer)` to set `claimed_at = now()` when it
  transitions a row to `PROCESSING`. Keep its existing `FOR UPDATE SKIP LOCKED` and its `service_role`
  restriction from `0041_restrict_event_outbox_claim.sql`. In `0053`
- [x] T045 [US4] Create `reap_stuck_outbox_events(p_timeout interval DEFAULT interval '5 minutes')
  RETURNS integer` — `SECURITY DEFINER`, selecting
  `status = 'PROCESSING' AND claimed_at < now() - p_timeout` with `FOR UPDATE SKIP LOCKED`, branching on
  the attempts ceiling per T041; `REVOKE ALL FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO
  service_role, postgres;`. In `0053`
- [x] T046 [US4] Schedule the reaper on pg_cron every 5 minutes, guarded so re-application does not
  duplicate the job. In `0053`
- [x] T047 [US4] Create `v_failed_outbox_events` `WITH (security_invoker = true)` behind an
  `is_admin()` predicate, exposing `id, handler_type, status, attempts, next_attempt_at, claimed_at,
  last_error, created_at` plus recipient/template fields extracted from `payload`. `security_invoker`
  is required so it does not become an RLS bypass the way `v_complaints` already is. In `0053`
- [x] T048 [US4] Create `admin_resend_outbox_event(p_event_id bigint) RETURNS jsonb` — `SECURITY
  DEFINER` with an internal `is_admin()` guard, resetting `status = 'PENDING'`, `attempts = 0`,
  `last_error = NULL`, `next_attempt_at = now()`, `claimed_at = NULL`; `REVOKE ALL FROM PUBLIC, anon;
  GRANT EXECUTE TO authenticated;`. In `0053`
- [x] T049 [US4] Write `last_error` on a failed dispatch in `supabase/functions/event-dispatcher/index.ts`
- [x] T050 [US4] Verify T041 and T042 pass (Green)

**Note**: the Flutter staff backlog screen is **deferred to feature 008** with the clean-architecture
rework (handoff decision 4 scope note). 007 ships the view and the RPC only.

**Checkpoint**: background dispatch recovers from worker crashes.

---

## Phase 7: User Story 5 — Explicit Administrative Roles & Permission Hierarchy (P3)

**Goal**: make `SUPER_ADMIN` reachable; purge `PRIEST`.

**Note on test-first**: assertions referencing `'SUPER_ADMIN'::public.app_role` cannot parse until
`0052` has been applied, so T054 follows T051 by necessity — recorded as a deliberate exception in
`plan.md`.

### Implementation for User Story 5
- [x] T051 [US5] Confirm `0052_super_admin_role.sql` (T003) is applied; every statement referencing the
  new label must live in `0053`, never in `0052`
- [x] T052 [US5] Update `is_super_admin()` to compare against `'SUPER_ADMIN'::public.app_role`. It
  currently exists and can never return true. In `0053`
- [x] T053 [US5] Purge dead `PRIEST` references from policies, routines, and
  `supabase/functions/_shared/` role guards, with no metadata fallbacks
- [x] T054 [US5] Add role assertions to `0053_security_fixes_test.sql`: `is_super_admin()` true for a
  `SUPER_ADMIN`, false for `ADMIN`; no catalog object still references `PRIEST`
- [x] T055 [US5] Amend `AGENTS.md:31`, which hardcodes `ADMIN|PRIEST|SUPER_ADMIN` as the admin-route
  invariant, to `ADMIN|SUPER_ADMIN`. Purging the role from code without amending the invariant leaves
  the constitution contradicting the schema

**Checkpoint**: role architecture aligned; super-admin usable.

---

## Phase 8: User Story 6 — Fault-Tolerant Reconciliation & Authenticated Cron Endpoints (P3)

**Goal**: transient gateway errors no longer strand payers; the two cron-driven endpoints stop
accepting anonymous callers; checkout fails fast on missing secrets.

### Tests for User Story 6 (write FIRST, ensure they FAIL) ⚠️
- [x] T056 [P] [US6] `supabase/functions/reconcile-payments/index_test.ts` — failing cases for a 502,
  a timeout, and an explicit terminal decline: the first two leave the payment `CREATED`, the third
  transitions it to failed
- [x] T057 [P] [US6] Failing cases asserting an unauthenticated POST to `reconcile-payments` and to
  `event-dispatcher` returns `401` with the frozen Arabic `UNAUTHORIZED` body

### Implementation for User Story 6
- [x] T058 [US6] Refactor `supabase/functions/reconcile-payments/index.ts` — replace the
  `index.ts:48-57` behaviour that calls `markPaymentFailed` on *any* non-2xx with `console.error` on the
  payment id and status plus `continue`. Because the sweep only re-selects `status = 'CREATED'`, the
  current code strands a real payer as `FAILED` with no booking, permanently
- [x] T059 [US6] Add inbound bearer authentication to `reconcile-payments/index.ts` and
  `event-dispatcher/index.ts`: constant-time comparison against `CRON_SECRET` or
  `SUPABASE_SERVICE_ROLE_KEY`, returning the existing frozen `401 UNAUTHORIZED`. Neither function
  performs *any* inbound check today. The pg_cron jobs already send the service-role bearer token, so
  no cron change is required, and **no new error code is introduced** — the contract is frozen
- [x] T060 [P] [US6] Add module-scope validation to `supabase/functions/paymob-checkout/index.ts`
  rejecting absent, empty, or `"0"` values for `PAYMOB_API_KEY`, `PAYMOB_INTEGRATION_ID`,
  `PAYMOB_IFRAME_ID`, `PAYMOB_HMAC_SECRET`. Two of these currently default to `"0"` and silently
  produce invalid checkout URLs
- [x] T061 [US6] Add the non-`"0"` placeholder Paymob values to `supabase/functions/.env` for local
  runs, since T060 makes the function refuse to boot without them and quickstart Gate 6 would otherwise
  fail for the wrong reason. Do **not** weaken T060 to make the gate green
- [x] T062 [US6] `deno test --allow-env --allow-net supabase/functions/` passes (Green)

**Checkpoint**: reconciliation survives gateway blips; cron endpoints are authenticated.

---

## Phase 9: Polish & Cross-Cutting Concerns

- [x] T063 Fix the `v_content_backlog` `priests` branch: restrict to internal storage paths
  (`photo_url !~ '^https?://'`) and exclude rows already covered by the `storage.objects` branch.
  `0037_seed_sample_church_data.sql` seeds absolute `https://images.unsplash.com/...` URLs, making
  seeded priests permanent false positives while storage-backed photos are counted twice. In `0053`
- [x] T064 Re-apply idempotently the changes that commit `f663168` made **in place** to
  `0043_faq_categories.sql` and `0044_storage_buckets.sql`, which `supabase db push` environments never
  received (`0051_storage_objects_rls_guard.sql` forward-migrates only the `storage.objects` RLS
  enable): 12 storage policies gaining `TO authenticated` — one also gaining `AND public.is_admin()` —
  and for `faq_categories` the `tenant_id` default change to `public.tenant_id()`, the admin policy's
  `TO authenticated` plus tenant predicate, the public read policy's `TO anon, authenticated`, and the
  replacement of `GRANT ALL` with granular `GRANT INSERT, UPDATE, DELETE`. In `0053`
- [x] T065 [P] Document in `AGENTS.md` the RLS carve-out for objects the migration role does not own
  (`storage.objects`), following the guarded idiom already used by `0048` and `0051`; and record that at
  least eleven commits on `main` (`4559dc9`, `74f5681`, `9354b66`, `7e0ee01`, `0da91fb`, `5a49583`,
  `f663168`, `f773831`, `01b0ffa`, `e3c529d`, `652647f`) edited already-numbered migrations in place,
  so `supabase db reset` is currently the only reliable route to a known-good schema
- [x] T066 [P] Document the single-tenant scaffolding explicitly (handoff decision 23): `tenant_id()`
  falls back to a hardcoded `'1'` and `handle_new_user()` inserts a literal `tenant_id = 1`. Harmless
  with one tenant, but it must be recorded as **incomplete multi-tenant groundwork, not a delivered
  capability**. Not changed by this feature
- [x] T067 [P] Delete the superseded `specs/005-admin-domain-layer/` and `specs/006-mobile-domain-layer/`
  directories (handoff decision 12) — both are untracked and replaced by the 007/008 split
- [x] T068 Run all 8 gates in `specs/007-backend-security-fixes/quickstart.md` (bash; suites piped over
  **stdin**, because `/tests` is not mounted inside `supabase_db_church`)
- [x] T069 Repository hygiene scan: no secrets, no `CREATE INDEX CONCURRENTLY` in migrations, no
  `GRANT ALL` in the new migrations, no residual `video`/`PRIEST` references, `cron.job` free of the
  `youtube-expiry` entry

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)**: no dependencies. **T002 blocks T009** — the negative-auth tests assert
  exceptions, which the current `AGENTS.md` invariant forbids.
- **Foundational (Phase 2)**: depends on Phase 1; blocks all stories. **T003 blocks T052** by
  transaction semantics, not merely by convention.
- **US1 (Phase 3, P1)**: after Phase 2. **T012 must be in the same migration as T011** — revoking DML
  and dropping the only policy without a replacement zeroes admin reads.
- **US2 (Phase 4, P1)**: after Phase 2. **T027 must follow T023, T024, T025, and T026** — dropping the
  column first leaves three uncompilable objects.
- **US3 (Phase 5, P2)**: after Phase 2. T031 must follow T039, or the admin video screen breaks at
  runtime before it is deleted.
- **US4 (Phase 6, P2)**: after Phase 2. **T043 blocks T044, T045, T047, T048** — the columns must exist
  before anything reads or writes them.
- **US5 (Phase 7, P3)**: after Phase 2, and specifically after T003.
- **US6 (Phase 8, P3)**: after Phase 2. **T060 blocks T061**, and T061 must land before quickstart
  Gate 6 is meaningful.
- **Polish (Phase 9)**: after all stories.

### Parallel opportunities

- T001 and T002 (different files).
- T005 and T006 (different test files).
- T020, T021, T022 (view contract vs. two concurrency scenarios; T020 is in a different file).
- T035, T036, T038, T039 (edge functions, mobile app, admin app — all distinct trees).
- T056, T057, T060 (different edge functions and test files).
- T065, T066, T067 (documentation and directory deletion).
- **Not parallel**: every task whose target is
  `0053_backend_security_and_correctness_fixes.sql` — T004, T011–T017, T023–T028, T031–T034, T043–T048,
  T063, T064.

---

## Implementation Strategy

### MVP first (US1 + US2)
1. Phase 1 and Phase 2, ending with a clean `db reset`.
2. US1 red → green, verifying both denial **and** the preserved admin reads.
3. US2 red → green, including the nine legacy suite updates.
4. Validate: the booking and payment security invariants hold, and `v_available_slots`'s column
   contract is unchanged.

### Incremental delivery (US3–US6)
1. Decommission video machinery — database, cron, edge, **both** apps.
2. Add outbox schema, reaper, admin read surface, and resend.
3. Align the role architecture and amend the invariant text with it.
4. Harden reconciliation and authenticate the cron endpoints.
5. Polish, then run all 8 quickstart gates.
