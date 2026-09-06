# Implementation Plan: Edge-Function Shared Kernel

**Branch**: `003-edge-function-kernel` | **Date**: 2026-08-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-edge-function-kernel/spec.md`

## Summary

Consolidate the 9 Supabase edge functions' duplicated cross-cutting behavior into two deep shared modules: `_shared/http.ts` (identity gate + single error responder, per contracts/) and `_shared/paymob.ts` (single payment-gateway adapter). Kills the review's findings: 4 divergent bearer gates (one unverified), 3 byte-identical Paymob token exchanges, 3 error dialects + plain-text, 8× failed-payment cleanup, silent non-atomic outbox fallback, e2e HMAC drift. Behavior-preserving (FR-013); verification moves in-function per Supabase's current guidance (research R1), `verify_jwt` declared explicitly per function.

## Technical Context

**Language/Version**: TypeScript on Deno (Supabase Edge Runtime); no SQL changes.

**Primary Dependencies**: `npm:@supabase/supabase-js@2` (existing), Paymob REST API (existing protocol), Deno test.

**Storage**: Supabase Postgres — untouched (behavior-preserving; no migrations in this feature).

**Testing**: `deno test` — shared suites in `functions/_tests/` (currently empty), per-function `*_test.ts` updated; pgTAP `supabase/tests/run_all.sql` as regression gate; manual auth sweep + credential scans (quickstart.md).

**Target Platform**: Supabase Edge Functions (local stack → hosted).

**Project Type**: web-service backend refactor.

**Performance Goals**: preserve existing; bearer endpoints that previously skipped verification now add one auth-server roundtrip (accepted, security > latency).

**Constraints**: FR-013 behavior-preserving; secrets env-only with loud startup failure (FR-010); no new tables/endpoints; ADR 0001 refund = manual queue (no auto refund API calls); prerequisites = the 3 audit blockers landed first (spec Assumptions).

**Scale/Scope**: 9 edge functions, 2 new shared modules, 1 config file, 1 e2e script edit.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`​.specify/memory/constitution.md` is an unfilled template — not ratified. Governing standards therefore come from **AGENTS.md Locked Decisions** (workspace instructions), which this plan checks against:

| Locked decision | Status |
|---|---|
| Edge Function Defense (bearer validation, upstream try/catch → FAILED + 502 UPSTREAM_ERROR, webhook validation, PAID idempotency) | **Directly implemented** by this feature — it is the enforcement mechanism |
| State RPCs & Outbox (drain contract) | Preserved; FR-009 removes only the non-atomic fallback that violated it |
| Secrets in edge functions/vault only | FR-010; prerequisite strips existing fallbacks |
| Migration Upgrade Path | N/A — no migrations |
| Repository Seams & Errors (Either) | Client-side follow-up (Assumptions); this feature fixes the backend half (error contract) |

**Post-Phase-1 re-check**: design artifacts (contracts/, data-model.md) introduce no schema, no new endpoints, no policy changes — no violations. Complexity Tracking table: not needed (no violations to justify).

## Project Structure

### Documentation (this feature)

```text
specs/003-edge-function-kernel/
├── plan.md              # This file
├── research.md          # Phase 0 — 6 decisions w/ rationale + alternatives
├── data-model.md        # Phase 1 — error codes, endpoint registry, gateway ops, lease
├── quickstart.md        # Phase 1 — 6-step validation guide
├── contracts/
│   ├── error-contract.md            # unified response shape + migration table
│   └── shared-module-interfaces.md  # seam + adapter interfaces
└── tasks.md             # Phase 2 (/speckit-tasks — NOT created yet)
```

### Source Code (repository root)

```text
supabase/
├── functions/
│   ├── _shared/
│   │   ├── http.ts          # NEW — auth(req) + respond() + CORS (folds in cors.ts)
│   │   ├── paymob.ts        # NEW — gateway adapter + hmacFields()
│   │   ├── client.ts        # existing
│   │   └── fake_supabase.ts # existing test fake
│   ├── _tests/              # FILLED — shared kernel suites (auth, respond, paymob)
│   ├── paymob-checkout/     # handler → seam + adapter; cleanup 8× → shared helper
│   ├── paymob-webhook/      # HMAC-only auth (no user tokens); imports hmacFields()
│   ├── event-dispatcher/    # refund via adapter; outbox fallback deleted (abort+log)
│   ├── reconcile-payments/  # adapter; res.json() wrapped → UPSTREAM_ERROR
│   ├── youtube-expiry/      # respond() only
│   ├── offline-sync/        # real verification via seam (was header-only)
│   ├── analytics-export/    # seam + staff gate; JSON errors (was plain text)
│   ├── otp-sms/             # seam
│   └── diagnostic-engine/   # seam + staff gate (deps-seam refactor deferred, cand. #5)
├── config.toml              # explicit [functions.<name>] verify_jwt = false ×9
└── e2e/book_pay_flow.mjs    # imports hmacFields(); deletes local txnFields

diagnostic_engine/deno_engine.ts   # prerequisite blocker: env-only creds (landed before this feature)
```

**Structure Decision**: single-repo monorepo unchanged; only `supabase/functions/_shared/` deepens. The seam is the delivery surface — one adapter per external concern (identity provider, Paymob), handlers become thin (test surface = seam, per codebase-design vocabulary).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations — table empty.
