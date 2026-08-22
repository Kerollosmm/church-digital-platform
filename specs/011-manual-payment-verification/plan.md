# Implementation Plan: Manual Payment Verification

**Branch**: `011-manual-payment-verification` | **Date**: 2026-08-22 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/011-manual-payment-verification/spec.md`

## Summary

Replace the never-onboarded Paymob online-checkout leg with admin-verified manual payments (ADR 0003): members submit transfer proof (channel, sender number, reference, amount, screenshot for wallets) after booking; admins approve/reject from a queue against the church's own statement; approval drives the existing `apply_payment` paid-transition into `AWAITING_CALL`. The gateway stack (~1,500 lines: checkout/webhook/reconcile functions, adapter, webhook RPC path, reconcile cron, six env secrets, mobile checkout flow) is deleted outright. Money guarantees — seat-lock expiry cron, booking state machine, single sanctioned payments write seam — are preserved untouched.

## Technical Context

**Language/Version**: PostgreSQL 16 (Supabase, plpgsql RPCs) · Deno (Edge Functions) · Flutter/Dart (mobile member app + admin web PWA)

**Primary Dependencies**: supabase-js v2 (functions), supabase_flutter (apps), go_router + Riverpod-style controllers (established repo patterns), Supabase Storage (proof images)

**Storage**: Supabase Postgres (new `payment_proofs`, `payout_channels` tables; existing `payments`, `bookings` untouched structurally except additive FK) + private `payment-proofs` storage bucket

**Testing**: Transactional SQL suites in `supabase/tests/` registered in `run_all.sql` (judged by parsed TAP output — never exit codes) · `deno test` for remaining functions · `flutter analyze` + `flutter test` both apps · E2E via local stack + `test-apps/` portals

**Target Platform**: Single-church deployment; Android-first member app, web PWA admin

**Performance Goals**: Admin review decision ≤30s per proof (single screen); submission ≤2min member-side; queue loads pending proofs only (bounded set)

**Constraints**: Zero credential literals; frozen five error codes (`UNAUTHORIZED|FORBIDDEN|BAD_REQUEST|UPSTREAM_ERROR|INTERNAL`) with catalog Arabic sentences; forward-only migrations; REVOKE-then-grant on every restricted RPC; `SET search_path` fixed on SECURITY DEFINER functions; Arabic-first UI, EGP amounts as integers

**Scale/Scope**: Parish volumes (tens of bookings/event); 3 new RPCs, 2 new tables, 1 bucket, 2 app flows, 1 deletion sweep across functions/tests/config/mobile

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|---|---|---|
| I. Test-First | PASS | Every FR lands as failing suite → implement → green → commit; registration in `run_all.sql` is an explicit task requirement |
| II. Security by Default | PASS | All three actions are SECURITY DEFINER RPCs behind `_shared/payments-gateway.ts`; REVOKE-then-grant; role read from `users.role` fail-closed; zero literals |
| III. Forward-Only Migrations | PASS | New numbered migrations + paired suites; applied migrations untouched; deletions ship as new DROP/revoke migrations where DB objects are involved |
| IV. Arabic-First | PASS | Frozen codes reused verbatim; member sees catalog `message_ar`; no new codes; UI strings via shared string catalog |
| V. Deep Modules, Thin Handlers | PASS | No new edge functions at all — money logic moves deeper into the SQL seam; the dispatcher's `PAYMOB_REFUND` branch is deleted rather than extended |
| Governance (Product Truth conflict) | RESOLVED PRE-PLAN | "Paymob is the only payment rail" contradicted this feature → [ADR 0003](../../docs/adr/0003-manual-payment-rail.md) recorded, constitution amended v1.2.0 before specification |

Post-design re-check: no violations introduced. New table follows tenant-invariant + RLS-guard + granular-grants rules (see data-model).

## Project Structure

### Documentation (this feature)

```text
specs/011-manual-payment-verification/
├── spec.md              # Completed (/speckit-specify)
├── research.md          # Market/code evidence + Phase 0 technical decisions
├── plan.md              # This file
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (RPC + storage + repository contracts)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
supabase/
├── migrations/
│   ├── 00XX_manual_payment_proofs.sql          # payment_proofs + payout_channels + payment_channel enum + bucket + grants
│   └── 00XX_drop_paymob_stack.sql              # drop webhook RPC path, unschedule reconcile cron, revoke legacy function grants
├── tests/
│   ├── 00XX_manual_payment_proofs_test.sql     # owner/non-owner, staff-only, idempotency, lifecycle, expiry composition
│   └── 00XX_drop_paymob_stack_test.sql         # legacy paths denied/absent
├── functions/
│   └── _shared/payments-gateway.ts             # EXTENDED: register submitPaymentProof / approvePaymentProof / rejectPaymentProof
│       # DELETED: _shared/paymob.ts, paymob-checkout/, paymob-webhook/, reconcile-payments/ (+ their *_test.ts),
│       #         offline-sync/ (separate commit, roadmap-confirmed)
├── config.toml                                 # paymob function blocks removed
apps/
├── mobile/lib/features/booking/
│   ├── payment_proof_screen.dart               # NEW: channel picker, fields, image attach, payout details
│   └── payment_redirect_screen.dart            # DELETED (with checkout-session model + controller wiring)
└── admin/lib/features/payments/
    ├── payment_review_queue_screen.dart        # NEW: pending proofs, thumbnail, approve/reject-with-reason
    ├── cash_received_sheet.dart                # NEW: direct cash marking
    └── payouts_config_screen.dart              # NEW: super-admin editable channels
```

**Structure Decision**: Follows the established monorepo seams exactly — SQL owns money state (conventions.md "SQL first"), no new Edge Function exists to defend, apps speak only through typed repositories returning `Either<Failure, T>` (AGENTS.md Repository Seams & Errors).

## Complexity Tracking

> No constitution violations to justify. The design *removes* complexity (three edge functions, one cron, one failure class) rather than adding it; the only new moving parts are two tables, one private bucket, and three RPCs inside the existing seam.
