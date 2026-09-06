# Implementation Plan: Review Findings Remediation

**Branch**: `010-fix-review-findings` | **Date**: 2026-08-21 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/010-fix-review-findings/spec.md`

## Summary

Close every verified finding from the 2026-08-21 project review before feature 008 builds on the same seams: collapse all payment writes in integration code onto SECURITY DEFINER RPCs and close the ownership-check gap in `transition_booking_status` (new forward migration); strip runtime/upstream message leaks from error payloads; remove credential literals from browser tooling and re-auth portals with seeded role accounts; delete the dead `is_admin_or_priest` call from admin login; sync conventions/handbook docs to shipped enums; give the admin app the same typed repository seam the mobile app already has; consolidate to the single `test-apps/` harness.

## Technical Context

**Language/Version**: TypeScript (Deno Deploy runtime) for edge functions · SQL (PostgreSQL 16, Supabase) · Dart 3 / Flutter for apps

**Primary Dependencies**: `supabase-js` (portals) · `supabase_flutter`, Riverpod, go_router (apps) · `_shared/http.ts`, `_shared/paymob.ts`, `_shared/messages.ts` kernel

**Storage**: PostgreSQL 16 via Supabase (RLS everywhere, Vault secrets)

**Testing**: TAP SQL suites via `node scripts/test-sql.js` (stdin, transactional BEGIN…ROLLBACK, registered in `supabase/tests/run_all.sql`) · `deno test --allow-env --allow-net supabase/functions/` · `flutter test` + `flutter analyze` (mobile & admin)

**Target Platform**: Local Supabase stack (`127.0.0.1:54321`) now; staging/prod later via forward migrations

**Project Type**: Monorepo remediation — backend SQL + edge functions + two Flutter apps + dev tooling

**Performance Goals**: No regressions; admin sign-in drops from 2 identity round-trips to 1

**Constraints**: Forward-only migrations (constitution III) · frozen five error codes · Arabic-first strings preserved verbatim · zero credential literals · every behavior change test-first

**Scale/Scope**: ~4 edge functions touched, 1 new migration (+test), 2 doc files, ~12 admin feature screens refactored, 1 harness deleted (~5k lines)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Test-First | PASS | Every US ships failing test → implement → green → commit; SQL tests registered in run_all.sql |
| II. Security by Default | PASS | Feature's purpose: enforce REVOKE-then-grant, zero credential literals, role-from-table decisions |
| III. Forward-Only Migrations | PASS | 0063 ownership gap fixed by NEW migration `0064_*`; no applied migration edited |
| IV. Arabic-First | PASS | No UI copy changes; error bodies reuse catalog `message_ar`; codes stay frozen five |
| V. Deep Modules, Thin Handlers | PASS | Payment writes centralize in `_shared/payments-gateway.ts`; admin screens get repositories; duplication treated as regression |

Post-design re-check (Phase 1): no violations introduced — see Complexity Tracking (empty).

## Project Structure

### Documentation (this feature)

```text
specs/010-fix-review-findings/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── api-contracts.md # RPC/HTTP/Dart seam contracts
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
supabase/
├── migrations/
│   └── 0064_transition_owner_guard.sql        # NEW — closes apply_payment bypass
├── tests/
│   ├── 0064_transition_owner_guard_test.sql   # NEW — denial + allowance pairs
│   └── run_all.sql                            # register 0064 test
└── functions/
    ├── _shared/
    │   ├── payments-gateway.ts                # NEW — single payment write seam over RPCs
    │   ├── paymob.ts                          # markPaymentFailed → gateway call
    │   └── http.ts                            # strip res.error?.message echoes
    ├── paymob-webhook/index.ts                # raw .from("payments") → gateway
    ├── paymob-checkout/index.ts               # payment creation → gateway
    ├── reconcile-payments/index.ts            # failure marking → gateway
    └── otp-sms/index.ts                       # stop echoing err.message/upstream body

apps/admin/lib/
├── core/auth/admin_auth_provider.dart         # delete dead RPC block + silent catch
└── features/<f>/<f>_repository.dart           # NEW per feature — typed seam
    (slots, bookings, manual_book, emergency_override, payments,
     complaints, announcements, content, analytics ×4)

docs/superpowers/plans/conventions.md          # §Enums synced to shipped types
AGENTS.md                                      # Admin role guard: ADMIN|SUPER_ADMIN

test-apps/                                     # survives; service-role client removed;
                                               # credentials generated at setup, untracked
test_portal/                                   # DELETED
```

**Structure Decision**: Existing monorepo layout reused; one new migration + shared module; admin mirrors mobile's `repositories/` pattern per feature directory.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| (none) | | |
