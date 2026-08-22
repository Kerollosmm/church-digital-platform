# Tasks: Manual Payment Verification

**Input**: Design documents from `/specs/011-manual-payment-verification/`

**Prerequisites**: plan.md · spec.md · research.md (§8 decisions D1–D6) · data-model.md · contracts/rpc-contracts.md · quickstart.md

**Tests**: INCLUDED — constitution Principle I (Test-First) is NON-NEGOTIABLE; every story ships failing test → implement → green → commit. SQL suite results judged by parsed TAP output, never exit codes (pgTAP false-green trap).

**Organization**: Grouped by user story (US1–US6 from spec.md). Owner decisions recorded 2026-08-22: full replacement (no dual rail), channels = Vodafone Cash / InstaPay / cash-in-person, screenshot required for wallets only. Governance: ADR 0003 + constitution v1.2.0 landed pre-plan; AGENTS.md + conventions.md §Enums synced.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files, no dependency on incomplete task)
- **[Story]**: owning user story
- Exact file paths in every description

## Path Conventions

Monorepo (per plan.md): `supabase/migrations/`, `supabase/tests/`, `supabase/functions/` (Deno+TS), `apps/mobile/lib/` + `apps/mobile/test/`, `apps/admin/lib/` + `apps/admin/test/`, `test-apps/`, `docs/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Baseline proof that all gates are green BEFORE any change.

- [x] T001 Run baseline gates and record counts: `node scripts/test-sql.js`, `deno test --allow-env --allow-net supabase/functions/`, `flutter analyze` + `flutter test` in `apps/mobile/` and `apps/admin/` — save summary to `.scratch/011-baseline.md`
- [x] T002 Create/verify feature branch `011-manual-payment-verification` (`git rev-parse --abbrev-ref HEAD`); spec-010 work must be merged or rebased first so migrations 0063–0065 are present

**Checkpoint**: Baseline green recorded; branch correct; 0065 is max applied migration.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Schema, storage, and seed data every story depends on. No user story work before this lands.

- [x] T003 [P] Write failing SQL test `supabase/tests/0066_manual_payment_foundations_test.sql`: transactional BEGIN…ROLLBACK fixtures asserting — (a) `payment_channel` enum exists with exactly `VODAFONE_CASH|INSTAPAY|CASH`; (b) `payment_proofs` CHECKs enforced (wallet without `image_path` rejected, CASH with image rejected, REJECTED without reason rejected); (c) unique partial index allows one PENDING proof per booking, rejects second; (d) RLS: member SELECT limited to own-booking proofs, anon zero rows; (e) `payout_channels` SELECT granted to authenticated, UPDATE denied to ADMIN, allowed to SUPER_ADMIN (row_count semantics, never exceptions); (f) seed idempotency: re-running seed leaves exactly one row per wallet channel; (g) identity sequence `payment_proofs_id_seq` usable by `authenticated`
- [x] T004 [P] Register test in `supabase/tests/run_all.sql` with `\ir 0066_manual_payment_foundations_test.sql`; run `node scripts/test-sql.js` and confirm 0066 FAILS (red)
- [x] T005 Create migration `supabase/migrations/0066_manual_payment_foundations.sql` per data-model.md: `payment_channel` enum; `payment_proofs` + `payout_channels` tables with all CHECK constraints, tenant defaults, `ENABLE ROW LEVEL SECURITY` before policies; member/admin storage policies for private bucket `payment-proofs` (path scheme `{tenant_id}/{booking_id}/{proof_id}.<ext>`, explicit `ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY`, granular DML `TO authenticated`, admin read via `public.is_admin()`); idempotent seed inserts (VODAFONE_CASH + INSTAPAY rows, Arabic display names); `GRANT USAGE, SELECT ON SEQUENCE`; forward-only
- [x] T006 Run `npx supabase db reset` then `node scripts/test-sql.js` — expect 0066 PASS (green); commit `feat(sql): 0066 payment proof + payout channel foundations`

**Checkpoint**: Foundation ready — story phases may begin.

---

## Phase 3: User Story 1 — Member pays by wallet and submits proof (Priority: P1) 🎯 MVP

**Goal**: Owner of a `PENDING_PAYMENT` booking submits channel/sender/reference/amount/image; proof recorded PENDING; nothing financial moves; non-owners denied with zero rows.

**Independent Test**: `node scripts/test-sql.js` shows 0067 suite passing owner-allow + non-owner-deny + validation-reject cases; member portal flow books and submits proof E2E; booking stays `PENDING_PAYMENT`.

### Tests for User Story 1 (write FIRST, verify FAIL)

- [ ] T007 [P] [US1] Write failing SQL test `supabase/tests/0067_submit_payment_proof_test.sql`: fixtures per conventions — (a) owner submit (VODAFONE_CASH with image path) returns proof id, creates PENDING proof + `CREATED` payment snapshot, booking status unchanged, zero `AWAITING_CALL`; (b) non-owner submit denied `FORBIDDEN`, zero rows in both tables; (c) wallet channel without image → `BAD_REQUEST`, zero rows; (d) CASH with image → `BAD_REQUEST`; (e) second PENDING proof for same booking → `BAD_REQUEST`; (f) submit against `AWAITING_CALL` booking → `BAD_REQUEST`; (g) anon execution denied; (h) audit rows written on success
- [x] T008 [P] [US1] Register in `supabase/tests/run_all.sql`; run `node scripts/test-sql.js` confirm 0067 FAILS (red)
- [ ] T009 [P] [US1] Write failing Deno test in `supabase/functions/_tests/payments_gateway_test.ts`: stub client asserting `submitPaymentProof(client, {...})` invokes RPC `submit_payment_proof` with mapped params and never touches `.from("payment_proofs")` outside the seam; confirm FAIL (export missing)

### Implementation for User Story 1

- [ ] T010 [US1] Create migration `supabase/migrations/0067_submit_payment_proof.sql`: `submit_payment_proof(bigint, public.payment_channel, text, text, int, text)` per contracts — SECURITY DEFINER, `SET search_path = ''`, REVOKE ALL from PUBLIC/anon/authenticated then `GRANT EXECUTE TO authenticated`; guard order: booking exists+tenant → ownership (`FORBIDDEN`) → status `PENDING_PAYMENT` (`BAD_REQUEST`) → channel/image consistency → no existing PENDING proof → wallet image object exists under caller prefix; writes snapshot via existing `create_pending_payment` then PENDING proof insert
- [x] T011 [US1] Run `npx supabase db reset` + `node scripts/test-sql.js` — 0067 green; commit `feat(sql): 0067 owner-only payment proof submission`
- [ ] T012 [US1] Extend `supabase/functions/_shared/payments-gateway.ts` with `submitPaymentProof` wrapper; run `deno test` green; commit with T013
- [ ] T013 [US1] Mobile proof flow: model `apps/mobile/lib/models/payment_proof_input.dart`; repository methods `submitPaymentProof` + `fetchPayoutChannels` in `apps/mobile/lib/repositories/booking_repository.dart` + `supabase_booking_repository.dart` (Either<Failure,T>, no raw exceptions); screen `apps/mobile/lib/features/booking/payment_proof_screen.dart` (channel picker, sender phone, reference, amount, image attach with preview, payout details copyable, Arabic strings via `apps/mobile/lib/services/app_strings.dart`); replace router payment entry in `apps/mobile/lib/app_router.dart`; storage upload under `{tenant_id}/{booking_id}/` prefix via repository only
- [ ] T014 [US1] Mobile tests: widget test `apps/mobile/test/features/booking/payment_proof_screen_test.dart` + repository test with fake client (real repository class, slot/proof-aware fakes) covering success, wallet-without-image failure, non-owner failure mapping to Arabic message; `flutter analyze` + `flutter test` green in `apps/mobile/`; commit `feat(mobile): payment proof submission flow`
- [ ] T015 [US1] Wire member proof flow into `test-apps/user.html` (upload + RPC call + status display) for manual verification harness

**Checkpoint**: SC-001 demonstrable — member submits proof E2E; booking untouched financially.

---

## Phase 4: User Story 2 — Admin verifies or rejects proofs (Priority: P1)

**Goal**: Staff-only approve (→ existing `apply_payment` → `AWAITING_CALL`) and reject (frozen Arabic reason, resubmittable) with idempotent double-approve and deterministic expiry races.

**Independent Test**: 0068 suite proves staff-allow/non-staff-deny (0 rows), idempotency, reject→resubmit→approve lifecycle, expiry-composition (PENDING proof still expires; orphan approval denied); admin portal queue decides E2E.

### Tests for User Story 2 (write FIRST, verify FAIL)

- [ ] T016 [P] [US2] Write failing SQL test `supabase/tests/0068_payment_decision_rpcs_test.sql`: (a) ADMIN + SUPER_ADMIN approve → proof APPROVED, reviewer/time set, payment `PAID` via `apply_payment`, booking `AWAITING_CALL`, WhatsApp `booking_payment_received` outbox row enqueued (US6 assertion rides here); (b) USER-role approve/reject denied `FORBIDDEN` zero rows; (c) double-approve (sequential + concurrent-style second call) → second denied `BAD_REQUEST`, exactly one transition, one outbox row; (d) reject with catalog code → REJECTED + reason, zero financial writes, member resubmits (0067 path) then approve succeeds; (e) reject with non-catalog code → `BAD_REQUEST`; (f) expiry composition: PENDING proof + `expire_stale_bookings()` → booking CANCELLED + seat freed + waiting-list promoted; approve on orphaned proof → `BAD_REQUEST`; (g) approve on booking already CANCELLED → payment lands `REFUND_PENDING`, no seat granted (existing 0012 semantics preserved)
- [ ] T017 [P] [US2] Register in `run_all.sql`; confirm 0068 FAILS (red)
- [ ] T018 [P] [US2] Write failing Deno tests in `supabase/functions/_tests/payments_gateway_test.ts` for `approvePaymentProof` / `rejectPaymentProof` wrappers (RPC name + param mapping, no direct table access); confirm FAIL

### Implementation for User Story 2

- [ ] T019 [US2] Create migration `supabase/migrations/0068_payment_decision_rpcs.sql`: `approve_payment_proof(bigint, text default null)` + `reject_payment_proof(bigint, text)` per contracts — SECURITY DEFINER, fixed search_path, REVOKE-then-`GRANT EXECUTE TO authenticated` (tier gate inside, fail-closed), `FOR UPDATE` row lock on PENDING proof, approve executes untouched `apply_payment`
- [ ] T020 [US2] `npx supabase db reset` + `node scripts/test-sql.js` — 0068 green; commit `feat(sql): 0068 staff-only proof decisions with idempotency`
- [ ] T021 [US2] Extend `supabase/functions/_shared/payments-gateway.ts` with decision wrappers; `deno test` green
- [ ] T022 [US2] Admin repository: `listPendingProofs` / `approveProof` / `rejectProof` in `apps/admin/lib/features/payments/payments_admin_repository.dart` (Result pattern, proof-aware fakes)
- [ ] T023 [US2] Admin queue UI: `apps/admin/lib/features/payments/payment_review_queue_screen.dart` — pending proofs with image thumbnail, claimed fields, one-screen approve / reject-with-catalog-reason picker; Arabic via existing strings pattern; route registered in `apps/admin/lib/app_router.dart`
- [ ] T024 [US2] Admin tests: `apps/admin/test/features/payments/payment_review_queue_test.dart` + repository test (real repository, fakes) covering approve success, reject-with-reason, non-staff failure mapping; `flutter analyze` + `flutter test` green in `apps/admin/`; commit `feat(admin): payment proof review queue`
- [ ] T025 [US2] Wire review queue into `test-apps/admin.html` (list PENDING proofs, approve/reject calls) for manual verification

**Checkpoint**: SC-002 + SC-004 + SC-005 demonstrable; money-complete MVP (US1+US2).

---

## Phase 5: User Story 3 — Cash taken in person (Priority: P2)

**Goal**: Staff mark cash received in one round-trip: APPROVED CASH proof (no image) + snapshot + `apply_payment`, identical financial semantics.

**Independent Test**: 0069 suite proves staff-allow/non-staff-deny, booking-status guard, conflict with existing PENDING proof; admin cash sheet E2E.

### Tests for User Story 3 (write FIRST, verify FAIL)

- [ ] T026 [P] [US3] Write failing SQL test `supabase/tests/0069_mark_cash_received_test.sql`: (a) ADMIN marks cash → APPROVED CASH proof with collector note + reviewer/time, payment `PAID`, booking `AWAITING_CALL`; (b) USER-role denied `FORBIDDEN` zero rows; (c) booking not `PENDING_PAYMENT` → `BAD_REQUEST`; (d) existing PENDING proof → `BAD_REQUEST` (decide it first); (e) amount ≤ 0 → `BAD_REQUEST`
- [ ] T027 [P] [US3] Register in `run_all.sql`; confirm FAIL (red)

### Implementation for User Story 3

- [ ] T028 [US3] Create migration `supabase/migrations/0069_mark_cash_received.sql`: `mark_cash_received(bigint, int, text default null)` per contracts — single transaction, tier gate, reuses `create_pending_payment` + `apply_payment`
- [ ] T029 [US3] Green gates + commit `feat(sql): 0069 cash-in-person marking`; extend `payments-gateway.ts` with `markCashReceived` wrapper + Deno test; admin cash sheet `apps/admin/lib/features/payments/cash_received_sheet.dart` (amount, collector note, Arabic) + repository method + widget/repository tests in `apps/admin/test/features/payments/`; wire into `test-apps/admin.html`; all gates green; commit `feat(admin): cash received marking`

**Checkpoint**: US3 independently functional.

---

## Phase 6: User Story 4 — Super-admin maintains payout details (Priority: P2)

**Goal**: Wallet numbers are data: super-admin edits, members always see current values, regular admins denied.

**Independent Test**: policy tests in 0066 suite already prove tier gates; admin config screen edits a channel E2E and member payment step reflects it.

### Implementation for User Story 4

- [ ] T030 [P] [US4] Admin repository: `listPayoutChannels` / `upsertPayoutChannel` in `apps/admin/lib/features/payments/payments_admin_repository.dart` with fake-client tests (super-admin allow, admin deny mapping)
- [ ] T031 [US4] Config screen `apps/admin/lib/features/payments/payouts_config_screen.dart`: per-channel Arabic display name, account number, holder name; visible read-only to ADMIN, editable to SUPER_ADMIN (UI gate mirrors RLS); route in `apps/admin/lib/app_router.dart`
- [ ] T032 [US4] Widget tests `apps/admin/test/features/payments/payouts_config_test.dart`; `flutter analyze` + `flutter test` green; commit `feat(admin): payout channels configuration`
- [ ] T033 [US4] Member-side verification: payment proof screen (T013) fetches live `payout_channels` — add repository test asserting displayed values come from the table, not constants

**Checkpoint**: US4 independently functional; parallelizable with Phases 4–5 after Phase 2.

---

## Phase 7: User Story 5 — Gateway stack deleted (Priority: P2)

**Goal**: Zero live Paymob references; suites green without deleted tests; deletion in one logical commit after replacement works.

**Independent Test**: grep sweeps return zero hits (functions, apps, tests, config; historical migrations excepted); `node scripts/test-sql.js` + `deno test` + both apps' gates green.

### Tests for User Story 5 (write FIRST, verify FAIL)

- [ ] T034 [P] [US5] Write failing SQL test `supabase/tests/0070_drop_paymob_stack_test.sql`: (a) `record_webhook_payment` does not exist / execute denied; (b) `mark_payment_failed` absent; (c) cron job `reconcile-payments` unscheduled (`cron.job` empty for name); (d) `event_outbox` contains zero `PAYMOB_REFUND` rows after purge; (e) legacy `payments.raw_webhook` column dropped (data-model: no gateway columns retained)
- [ ] T035 [P] [US5] Register in `run_all.sql`; confirm FAIL (red)

### Implementation for User Story 5

- [ ] T036 [US5] Create migration `supabase/migrations/0070_drop_paymob_stack.sql`: purge `PAYMOB_REFUND` outbox rows then `ALTER TYPE event_handler_type DROP VALUE 'PAYMOB_REFUND'`; drop `record_webhook_payment` + `mark_payment_failed` (REVOKE-then-DROP), drop `payments.raw_webhook`; unschedule `reconcile-payments` cron; keep `create_pending_payment` + `apply_payment` (approval path depends on them)
- [ ] T037 [US5] Delete function code: `supabase/functions/paymob-checkout/`, `paymob-webhook/`, `reconcile-payments/` (incl. `index_test.ts` each), `supabase/functions/_shared/paymob.ts`; remove `PAYMOB_REFUND` branch + `paymobApiKey` wiring from `supabase/functions/event-dispatcher/index.ts`; update `supabase/functions/_tests/zero_leak_sweep_test.ts` endpoint list + `payments_gateway_test.ts` (drop `recordWebhookPayment` wrapper and its tests from `_shared/payments-gateway.ts`)
- [ ] T038 [US5] Config + mobile deletion: remove `[functions.paymob-checkout]` / `[functions.paymob-webhook]` from `supabase/config.toml`; delete `apps/mobile/lib/models/booking_checkout_session.dart`, `apps/mobile/lib/features/booking/payment_redirect_screen.dart`, checkout methods in `apps/mobile/lib/repositories/{booking_repository,supabase_booking_repository}.dart` + `controllers/booking_flow_controller.dart` + router/routes references
- [ ] T039 [US5] Verification: `npx supabase db reset` + full `node scripts/test-sql.js` + `deno test --allow-env --allow-net supabase/functions/`; grep sweeps (`grep -ri paymob supabase/functions apps/mobile/lib apps/admin/lib supabase/config.toml` and `grep -rn "PAYMOB_" supabase/functions`) → zero hits; `flutter analyze` + `flutter test` both apps; commit `feat(payments): delete Paymob stack — manual verification is the only rail (ADR 0003)`
- [ ] T040 [US5] Docs sync with deletion: strip Paymob webhook/HMAC/retry sections from `docs/superpowers/plans/conventions.md` (§Repository Layout, §External Integrations, §Slot Locking payretry note, §Backend Logic event_outbox description), update `docs/external-onboarding-checklist.md` (Paymob entry → retired per ADR 0003); commit `docs: retire Paymob conventions per ADR 0003`

**Checkpoint**: SC-003 demonstrable — zero live references, all suites green.

---

## Phase 8: User Story 6 — Notifications on verification (Priority: P3)

**Goal**: Payment-received notification fires on approval with unchanged template/payload; provider absence stays non-blocking.

**Independent Test**: 0068 assertion (T016a) already proves enqueue on approve; this phase only verifies template/payload shape and best-effort degradation.

- [ ] T041 [P] [US6] Verify + adjust template wiring: confirm `event-dispatcher` WhatsApp `booking_payment_received` payload built from approval path matches pre-011 shape (link param); if dispatcher test coverage lacks a proof-approval-shaped case, extend `supabase/functions/_tests/` accordingly; run `deno test` green; commit only if code changed: `chore(functions): notification trigger follows proof approval`

---

## Phase 9: Polish & Cross-Cutting Concerns

- [ ] T042 [P] Confirm `offline-sync` roadmap status with owner; if confirmed dead, delete `supabase/functions/offline-sync/` + references in its own commit `chore(functions): remove uncalled offline-sync` (spec FR-015 contingency)
- [ ] T043 Run full `specs/011-manual-payment-verification/quickstart.md` walkthrough end-to-end on local stack (both portals, all six sections) and record results in `.scratch/011-quickstart-results.md`
- [ ] T044 Update `memory-bank/activeContext.md` + `memory-bank/progress.md`: 011 landed, lifecycle diagram (proof → approve → AWAITING_CALL), next step feature 008
- [ ] T045 Final gates: `node scripts/test-sql.js` + `deno test` + both apps analyze/test — all green; verify every task above has its own commit (`git log --oneline` review)

**Checkpoint**: SC-001…SC-007 all demonstrable; feature complete.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none — start immediately
- **Foundational (Phase 2)**: depends on Setup; BLOCKS all user stories
- **US1 (Phase 3)**: depends on Phase 2 — MVP entry point
- **US2 (Phase 4)**: depends on US1 (proofs must exist to decide); completes the money loop
- **US3 (Phase 5)**: depends on US2 (reuses decision semantics + apply path)
- **US4 (Phase 6)**: depends only on Phase 2 — may run in parallel with Phases 4–5
- **US5 (Phase 7)**: depends on US1–US4 (replacement proven before deletion)
- **US6 (Phase 8)**: rides US2's approval assertion; independent code change unlikely
- **Polish (Phase 9)**: depends on all desired stories

### Within Each Story

Tests written FIRST and confirmed FAIL (red) before any migration/code; migrations before app wiring; repositories before screens; story checkpoint before next priority.

### Parallel Opportunities

- T003/T004 (SQL red) parallel with T009-style Deno red tests in later stories
- US4 (T030–T033) parallel with US2/US3 phases (disjoint files)
- T041, T042 parallel with each other after Phase 7

---

## Parallel Example: User Story 2

```bash
# Red tests together:
Task: "SQL suite 0068_payment_decision_rpcs_test.sql (T016)"
Task: "Deno wrapper tests in payments_gateway_test.ts (T018)"
# Then sequentially: migration T019 → seam T021 → repository T022 → queue UI T023 → tests T024
```

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Phase 1 → Phase 2 → Phase 3 → Phase 4
2. **STOP and VALIDATE**: member submits proof, admin approves, booking reaches `AWAITING_CALL` — the money loop is complete; Paymob could be deleted tomorrow
3. US3–US6 + deletion follow without touching the MVP seam

### Incremental Delivery

Each story checkpoint adds value independently: submission (US1) → decisions (US2) → cash (US3) → config (US4) → deletion (US5) → notifications (US6). Tree stays green at every commit (FR-015 of spec).

### Notes

- Every SQL change = forward-only migration + registered suite; suite results parsed, never trusted by exit code
- Every restricted RPC: `SET search_path` fixed + REVOKE ALL + granular grant + negative-authorization assertions
- Arabic strings verbatim via shared catalogs; frozen five codes only
- Deletion commit (T036–T039) is atomic: migration + code + config + tests together
