# Tasks: Review Findings Remediation

**Input**: Design documents from `/specs/010-fix-review-findings/`

**Prerequisites**: plan.md · spec.md · research.md · data-model.md · contracts/api-contracts.md · quickstart.md

**Tests**: INCLUDED — constitution Principle I (Test-First) is NON-NEGOTIABLE; every story ships failing test → implement → green → commit.

**Organization**: Grouped by user story (US1–US7 from spec.md). Clarifications recorded 2026-08-21: keep `test-apps/`, delete `test_portal/`; admin refactor covers ALL existing features; privileged portal workflows re-auth via seeded accounts. Post-analyze amendments (F1/F2): 0064 adds `create_pending_payment` + `mark_payment_failed` RPCs; leak-assertion sweep across all endpoint suites.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files, no dependency on incomplete task)
- **[Story]**: owning user story
- Exact file paths in every description

## Path Conventions

Monorepo (per plan.md): `supabase/migrations/`, `supabase/tests/`, `supabase/functions/` (Deno+TS), `apps/admin/lib/` + `apps/admin/test/`, `apps/mobile/`, `test-apps/`, `docs/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Baseline proof that all gates are green BEFORE any change — remediation must never chase pre-existing red.

- [X] T001 Run baseline gates and record counts: `node scripts/test-sql.js` (expect 54/54), `deno test --allow-env --allow-net supabase/functions/` (expect 84/84), `flutter analyze` + `flutter test` in `apps/mobile/` and `apps/admin/` — save summary to `.scratch/010-baseline.md`
- [X] T002 Create feature branch `010-fix-review-findings` from `main` if not already active (`git rev-parse --abbrev-ref HEAD`)

**Checkpoint**: Baseline green recorded. Any pre-existing red is documented, not fixed silently.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No shared blocking infrastructure needed — stories touch disjoint files by design. Intentionally empty.

**Checkpoint**: None required — user stories may begin immediately after Phase 1.

---

## Phase 3: User Story 1 — Payment writes through one sanctioned seam (Priority: P1) 🎯 MVP

**Goal**: Zero direct `payments` table writes outside the RPC-calling gateway; non-owner cannot advance another member's booking; FAILED/CREATED transitions get dedicated RPCs.

**Independent Test**: `node scripts/test-sql.js` shows 0064 suite passing denial+allowance pairs (incl. new RPCs); grep over `supabase/functions/` for `.from("payments")` matches only `_shared/payments-gateway.ts`; deno suite green.

### Tests for User Story 1 (write FIRST, verify FAIL)

- [X] T003 [P] [US1] Write failing SQL test `supabase/tests/0064_transition_owner_guard_test.sql`: transactional BEGIN…ROLLBACK fixtures — (a) authenticated non-owner calling `transition_booking_status(p_action='apply_payment', p_new_status='AWAITING_CALL')` on another user's PENDING_PAYMENT booking is denied with zero rows changed; (b) owner same call succeeds; (c) service_role succeeds; (d) `mark_payment_failed` denied for authenticated caller (zero rows), succeeds for service_role, leaves PAID rows untouched, idempotent on already-FAILED; (e) `create_pending_payment` inserts CREATED row with no status advance, owner or service_role allowed; explicit fixtures INSERT users/bookings/payments per conventions; assert audit rows on success paths
- [X] T004 [P] [US1] Register test in `supabase/tests/run_all.sql` with `\ir 0064_transition_owner_guard_test.sql`; run `node scripts/test-sql.js` and confirm 0064 FAILS (red)
- [X] T005 [P] [US1] Write failing Deno tests in `supabase/functions/_tests/payments_gateway_test.ts`: stub service client asserting `createPendingPayment` / `markPaymentFailed` / `recordPaidPayment` each invoke their named RPC (`create_pending_payment` / `mark_payment_failed` / `record_booking_payment`+`apply_payment`) with mapped params and NEVER call `.from("payments")`; run `deno test` confirm FAIL (module missing)

### Implementation for User Story 1

- [X] T006 [US1] Create migration `supabase/migrations/0064_transition_owner_guard.sql`: (1) recreate `public.transition_booking_status` with guard `is_admin() OR v_book.user_id = auth.uid() OR auth.role() = 'service_role'` for ALL actions (delete `p_action <> 'apply_payment'` escape hatch), drop stale `'PRIEST'` from role list; (2) add additive `public.create_pending_payment(bigint, numeric, text)` insert-only RPC per contracts §2; (3) add additive `public.mark_payment_failed(bigint)` RPC — FAILED from CREATED/PENDING only, idempotent, never touches PAID, service_role-only; all three: `SET search_path = public`, REVOKE ALL FROM PUBLIC/anon/authenticated then granular GRANTs per contracts; forward-only, no edits to 0063
- [X] T007 [US1] Run `npx supabase db reset` then `node scripts/test-sql.js` — expect 55/55 PASS (green); commit `fix(sql): 0064 close ownership bypass, add payment lifecycle RPCs`
- [X] T008 [US1] Create `supabase/functions/_shared/payments-gateway.ts`: export `createPendingPayment(client, {bookingId, amount, gatewayRef})` → `create_pending_payment`, `markPaymentFailed(client, paymentId)` → `mark_payment_failed`, `recordPaidPayment(client, paymentId)` → `apply_payment`; owner-initiated recording path → `record_booking_payment`; zero `.from("payments")` anywhere except this file
- [X] T009 [US1] Rewire `supabase/functions/paymob-webhook/index.ts` (~lines 79–115): replace direct insert/update of `payments` with gateway calls (`createPendingPayment` / `markPaymentFailed` / paid path); keep HMAC verification, PAID idempotency, positive-int validation untouched
- [X] T010 [US1] Rewire `supabase/functions/_shared/paymob.ts` `markPaymentFailed` (~line 150) to delegate to gateway; remove its error-swallowing catch (let gateway errors propagate)
- [X] T011 [US1] Rewire `supabase/functions/paymob-checkout/index.ts` (~lines 107–131): payment row creation via `gateway.createPendingPayment`; remove direct `.insert({status:"CREATED"})` and `.update({merchant_order_id})`
- [X] T012 [US1] Rewire `supabase/functions/reconcile-payments/index.ts` (~line 80) failure marking via gateway
- [X] T013 [US1] Extend `supabase/functions/_tests/payments_gateway_test.ts` coverage to webhook/checkout/reconcile paths using the stubbed gateway; run `deno test` green; commit `fix(functions): route all payment writes through payments-gateway seam`

**Checkpoint**: SC-001 (audit grep = 0 sites) and SC-002 (denial test passes) demonstrable independently.

---

## Phase 4: User Story 2 — Error responses leak nothing (Priority: P1)

**Goal**: Every failure body = frozen code + catalog Arabic sentence only — asserted by EVERY endpoint's suite.

**Independent Test**: deno failure-path tests assert absence of library/upstream substrings across ALL endpoint suites; suite green.

### Tests for User Story 2 (write FIRST, verify FAIL)

- [X] T014 [P] [US2] Extend `supabase/functions/_tests/http_test.ts`: force expired/malformed bearer token → assert body has `error` + `message_ar` and does NOT contain substrings of the underlying auth-library message; confirm FAIL against current `supabase/functions/_shared/http.ts` (~lines 113, 132)
- [X] T015 [P] [US2] Add failing cases to the existing otp-sms deno test file in `supabase/functions/_tests/`: upstream Meta error → assert response contains `UPSTREAM_ERROR` + catalog Arabic sentence and NO raw exception/provider payload; confirm FAIL
- [X] T016 [P] [US2] Leak-assertion sweep (FR-005): extend each remaining endpoint suite in `supabase/functions/_tests/` (event-dispatcher, analytics-export, offline-sync, diagnostic-engine, reconcile-payments, paymob-checkout, paymob-webhook) with one failure-path case asserting body contains frozen code + catalog Arabic and NO library/exception/upstream substrings; where a suite lacks any failure-path test, add a minimal one through the shared helper; confirm new assertions FAIL where leaks exist, PASS where helper already clean

### Implementation for User Story 2

- [X] T017 [US2] Fix `supabase/functions/_shared/http.ts` (~lines 113, 132): drop `res.error?.message ?? …` / `error?.message ?? …` echoes; return frozen code + `messageFor(code)` only; log detail server-side via existing structured logger
- [X] T018 [US2] Fix `supabase/functions/otp-sms/index.ts` (~lines 33–37, 108–118): wrap upstream send in try/catch that logs provider detail server-side and returns `UPSTREAM_ERROR` + catalog sentence; no new codes (frozen five only)
- [X] T019 [US2] Run `deno test` green across ALL suites incl. sweep; commit `fix(functions): enforce zero-leak error contract across all endpoints`

**Checkpoint**: SC-003 demonstrable (every endpoint's suite asserts no leaks).

---

## Phase 5: User Story 3 — No credentials in browser tooling (Priority: P1)

**Goal**: Zero service-role JWTs / password literals committed; portals authenticate as seeded roles over anon client.

**Independent Test**: repo-wide scan returns zero literals; `test-apps/run.ps1` serves harness and superadmin flows work signed-in as seeded SUPER_ADMIN.

### Tests for User Story 3 (verification-first)

- [X] T020 [P] [US3] Add scan step to `test-apps/run.ps1`: fail startup if scan for `SERVICE_ROLE|password123` matches any committed file under `test-apps/` (excluding generated untracked credentials file); document expected-empty result in output

### Implementation for User Story 3

- [X] T021 [US3] Strip privileged client from `test-apps/shared/supabase-client.js`: remove custom-key parameter (~line 59) and service-role admin factory (~line 71 comment + code); factory constructs anon-key clients only
- [X] T022 [US3] Update `test-apps/shared/test-accounts.js`: replace literal `'password123'` with passwords read from untracked generated file (`test-apps/.local-credentials.json`, gitignored); add SUPER_ADMIN seeded account entry if absent
- [X] T023 [US3] Update `test-apps/run.ps1` to generate random passwords per run into the untracked file and seed/update matching auth users via local Supabase admin API before serving; add `test-apps/.local-credentials.json` to `.gitignore`
- [X] T024 [US3] Re-auth superadmin flows in `test-apps/superadmin/app.js` (+ `test-apps/admin/app.js` where it used the privileged client): sign-in as seeded SUPER_ADMIN over anon client; decision rule for manual fallback — a workflow drops to documented manual checklist in `docs/ops/runbook.md` ONLY if it touches a path denied to anon+seeded-role accounts; everything else re-auths
- [X] T025 [US3] Run scan (zero matches) + full harness smoke (`test-apps/run.ps1`, exercise user/admin/superadmin happy paths); commit `fix(test-apps): remove credential literals, re-auth portals with seeded role accounts`

**Checkpoint**: SC-004 demonstrable.

---

## Phase 6: User Story 4 — Admin login stops calling deleted function (Priority: P2)

**Goal**: One identity round-trip; no request to removed `is_admin_or_priest`; no silent catch-through.

**Independent Test**: `flutter test apps/admin/` green incl. new auth test; manual sign-in shows single role lookup.

### Tests for User Story 4 (write FIRST, verify FAIL)

- [X] T026 [US4] Write failing widget/unit test `apps/admin/test/core/auth/admin_auth_rpc_test.dart`: fake client asserts NO `rpc('is_admin_or_priest')` call during role verification, exactly one `from('users').select('role')` query, USER-role denied with unchanged Arabic message, ADMIN allowed; run `flutter test` confirm FAIL (current code makes the dead call)

### Implementation for User Story 4

- [X] T027 [US4] Edit `apps/admin/lib/core/auth/admin_auth_provider.dart` (~lines 114–134): delete dead RPC try/catch block and `isAllowed` flag; decision solely from stored role vs `allowedRoles`; every branch's outcome explicit (no swallow-to-fallthrough)
- [X] T028 [US4] Run `flutter analyze` + `flutter test` in `apps/admin/` green; commit `fix(admin): drop dead is_admin_or_priest call from auth flow`

**Checkpoint**: SC-005 demonstrable.

---

## Phase 7: User Story 5 — Engineering docs match shipped schema (Priority: P2)

**Goal**: Enumerations diff empty against live types; handbook guard names real tiers.

**Independent Test**: quickstart §5 SQL enum dump compared line-by-line to conventions.md §Enums — zero differences.

- [X] T029 [US5] Dump live enums via quickstart §5 query (`pg_type`/`pg_enum`) and paste result into `.scratch/010-enum-truth.txt` as source of truth
- [X] T030 [US5] Sync `docs/superpowers/plans/conventions.md` §Enums (~lines 56–68) value-for-value from `.scratch/010-enum-truth.txt`: `slot_status = OPEN|CLOSED`, `waitlist_status = WAITING|OFFERED`, `role = USER|ADMIN|SUPER_ADMIN`; annotate retired values with pointers (PRIEST removal → `docs/adr/0002-video-to-event-booking-pivot.md` + spec 009 US5); verify payment/outbox/complaint enums against dump too — nothing invented
- [X] T031 [US5] Update `AGENTS.md` Admin UI Role Guard locked decision: `ADMIN|SUPER_ADMIN` (drop PRIEST) with one-line pointer to ADR-0002; commit `docs: sync enums and role guard to shipped schema`

**Checkpoint**: SC-006 demonstrable.

---

## Phase 8: User Story 6 — Admin screens stop touching database directly (Priority: P3)

**Goal**: Zero direct data-layer calls in admin feature screens; typed repositories per feature; no `dynamic` handles.

**Independent Test**: grep over `apps/admin/lib/features/**/*_screen.dart` for `.from(|.rpc(|Supabase.instance` returns nothing; full admin suite green.

### Tests for User Story 6 (write/adapt FIRST per feature)

- [X] T032 [P] [US6] Add repository contract tests in `apps/admin/test/features/content/content_repository_test.dart` exercising REAL repository class with slot-aware fakes (pattern: mobile `apps/mobile/test/helpers/fakes.dart`) — cover success + Failure mapping; extend same pattern per feature below as each repository lands

### Implementation for User Story 6 (order: pattern-setter → bulk)

- [X] T033 [US6] Formalize typed interface in `apps/admin/lib/features/content/content_repository.dart` and migrate `apps/admin/lib/features/content/announcements_admin_screen.dart` off direct `.from('announcements')` insert/delete onto it
- [X] T034 [P] [US6] Create `apps/admin/lib/features/slots/slots_admin_repository.dart` (list slots, set slot status) and migrate `slots_admin_screen.dart` off direct queries
- [X] T035 [P] [US6] Create `apps/admin/lib/features/bookings/manual_book_repository.dart` + `emergency_override_repository.dart` (available-slots read + RPC call each) and migrate both screens off `dynamic _db`
- [X] T036 [P] [US6] Create `apps/admin/lib/features/complaints/complaints_admin_repository.dart` (v_complaints read + decrypt RPC) and migrate `complaints_admin_screen.dart`
- [X] T037 [P] [US6] Create `apps/admin/lib/features/payments/payments_admin_repository.dart` and migrate `payments_admin_screen.dart`
- [X] T038 [US6] Create `apps/admin/lib/features/analytics/analytics_repository.dart` (four view readers: bookings/payments/utilization + revenue series) and migrate `bookings_screen.dart`, `payments_screen.dart`, `utilization_screen.dart`, `attendance_chart_widget.dart`, `revenue_chart_widget.dart`
- [X] T039 [US6] Type-tighten `apps/admin/lib/features/bookings/bookings_provider.dart` (replace dynamic fn dispatch with explicit named methods) and `apps/admin/lib/app_router.dart` client passing (remove `database is SupabaseClient ? … :` fallback ~line 209)
- [X] T040 [US6] Delete every remaining `dynamic get _db` handle in `apps/admin/lib/`; run grep proof (zero screen-level calls, zero dynamic DB handles); `flutter analyze` + `flutter test` green with Arabic strings/behavior unchanged; commit `refactor(admin): typed repository seam for all features`

**Checkpoint**: SC-007 demonstrable.

---

## Phase 9: User Story 7 — One browser test suite (Priority: P3)

**Goal**: Exactly one harness (`test-apps/`); `test_portal/` gone.

**Independent Test**: `Test-Path test_portal` False; harness smoke passes.

- [X] T041 [US7] Verify no unique logic exists only in `test_portal/` worth porting (diff flow coverage vs `test-apps/`); note findings in commit message body
- [X] T042 [US7] Delete `test_portal/` directory (`git rm -r test_portal/`); confirm `.github/workflows/` references neither harness path incorrectly (update CI if it referenced test_portal)
- [X] T043 [US7] Dedupe check in `test-apps/`: confirm auth/request/toast helpers exist once in `shared/` (extract duplicates between `user/app.js`, `admin/app.js`, `superadmin/app.js` into `shared/` if found); run harness smoke; commit `chore(test-apps): consolidate to single browser harness`

**Checkpoint**: SC-008 demonstrable.

---

## Phase 10: Polish & Cross-Cutting Concerns

- [X] T044 [P] Re-run FULL quickstart.md §1–§6 validation end-to-end; record results in `.scratch/010-final-validation.md` (SC-001…SC-010 checklist)
- [X] T045 [P] Update `memory-bank/progress.md` + `memory-bank/activeContext.md` with remediation outcomes and gate counts
- [X] T046 Verify commit series: one logical `fix|refactor|docs|chore(scope):` commit per remediation area referencing the review finding closed (FR-016); no mixed-concern commits (the bab9bc9 anti-pattern)
- [X] T047 Final two-axis self-review of cumulative diff vs AGENTS.md locked decisions + conventions.md (clean-code-guard review mode); file any new finding as follow-up issue, do not expand scope

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: immediate; blocks everything (baseline truth)
- **Phases 3–9 (US1–US7)**: mutually independent — disjoint files; execute in priority order P1→P3 or parallelize across sessions
- **Within US1**: T003–T005 (red) → T006–T007 (SQL green) → T008 (gateway) → T009–T012 (rewires; sequential-safe, independent once T008 lands) → T013
- **Within US2**: T014–T016 (red incl. sweep) → T017–T018 (fixes) → T019 (all green)
- **US7 after US3 preferred** (portal already credential-clean when deleted); otherwise independent

### Parallel Opportunities

- T003/T004/T005 red-test writing (different files)
- US2 ∥ US3 ∥ US4 ∥ US5 entirely (disjoint trees: functions helpers ∥ test-apps ∥ apps/admin auth ∥ docs)
- Inside US2: T014/T015/T016 all [P]
- Inside US6: T034–T037 all [P] (distinct feature dirs)
- T044/T045 [P]

---

## Parallel Example: P1 stories across sessions

```text
Session A: US1 (T003→T013)    — supabase/migrations + functions payment paths
Session B: US2 (T014→T019)    — functions/_shared/http.ts + otp-sms + sweep
Session C: US3 (T020→T025)    — test-apps/
Session D: US4+US5 (T026→T031) — apps/admin auth + docs
```

---

## Implementation Strategy

- **MVP first**: US1 alone closes the money-boundary HIGH findings — shippable, valuable increment; STOP and validate at its checkpoint
- **Incremental**: each US ends green + committed; any checkpoint halt leaves tree releasable
- **Risk order**: money boundary (US1) before 008; structural seam (US6) before 008 UI; docs (US5) before 008 planning reads them

## Notes

- Every SQL test transactional (BEGIN…ROLLBACK) with explicit fixtures; registered in run_all.sql
- Forward-only migrations: 0063 untouchable; fixes land in 0064 (owner guard + two additive payment RPCs)
- Frozen five error codes; catalog Arabic reused verbatim
- Commit after each checkpoint; conventional scopes: `fix(sql)`, `fix(functions)`, `fix(admin)`, `fix(test-apps)`, `refactor(admin)`, `docs`, `chore(test-apps)`




