# Research: Review Findings Remediation

**Feature**: 010-fix-review-findings · **Date**: 2026-08-21

No `NEEDS CLARIFICATION` unknowns remained after clarify (3 questions answered). This file records the design decisions taken while grounding each remediation in the actual code.

## D1 — Payment write seam shape

**Decision**: New `_shared/payments-gateway.ts` module. Exports one function per state intent — `createPendingPayment`, `markPaymentFailed`, `recordPaidPayment` — each calling its dedicated SECURITY DEFINER RPC: `create_pending_payment` (new, 0064), `mark_payment_failed` (new, 0064), and existing `record_booking_payment`/`apply_payment` respectively. No function outside the gateway may call `.from("payments")`.

**Rationale**: Constitution V (one seam per concern) + AGENTS.md money-boundary lock. Verified against migrations: only `apply_payment` (0012/0028), `mark_payment_refunded` (0046), and `record_booking_payment` (0063) exist today — there is NO RPC for the `FAILED` transition or insert-only creation, which is exactly why the raw updates crept in. 0064 therefore adds the two missing RPCs additively; FAILED never touches PAID rows so refund-race semantics stay intact.

**Alternatives considered**: (a) per-function inline RPC calls — rejected, re-scatters knowledge; (b) PostgREST-only with RLS — rejected, service-role writes bypass RLS so RPCs are the only guarded door; (c) reusing `mark_payment_refunded` for failures — rejected, wrong state semantics.

## D2 — Checkout payment creation path

**Decision**: Checkout's direct insert of a `CREATED` payment row moves behind `gateway.createPendingPayment()` → new additive RPC `create_pending_payment(p_booking_id, p_amount, p_gateway_ref)` (insert-only, no advance). The advance to `AWAITING_CALL` stays inside `apply_payment`, invoked by the same gateway only after Paymob confirms. Both new RPCs ship inside migration 0064 with registered tests.

**Rationale**: Resolved the former hedge: a dedicated insert-only RPC beats a mode flag on `record_booking_payment` (no boolean-flag parameter; one procedure per intent mirrors the gateway shape). SQL surface grows additively; nothing existing changes behavior.

## D3 — Ownership-gap fix (the 0063 bypass)

**Decision**: Migration `0064_transition_owner_guard.sql` recreates `transition_booking_status` with the guard: allow when caller is admin-tier (`is_admin()`), OR booking owner (`user_id = auth.uid()`), OR service role (`auth.role() = 'service_role'`) — the `p_action <> 'apply_payment'` escape hatch is deleted. Stale `'PRIEST'` entry in the role list removed in the same rewrite. REVOKE-then-grant repeated per hardening rule.

**Rationale**: Line 35 of 0063 lets any authenticated caller pass `p_action='apply_payment'` and skip the owner check entirely. Owner-initiated payments still pass because the owner IS the caller in that flow; service_role passes via explicit role check since its `auth.uid()` is null.

**Alternatives considered**: editing 0063 in place — forbidden (constitution III); trigger-based veto — rejected, hides the rule from the function readers who need it.

## D4 — Error-leak remediation pattern

**Decision**: `_shared/http.ts` auth-failure paths stop copying `res.error?.message` / `error?.message` into the payload; they return code + catalog `message_ar` only. `otp-sms` wraps upstream send in try/catch that logs details server-side (structured log) and returns `UPSTREAM_ERROR` + catalog sentence. No new codes.

**Rationale**: Frozen contract (constitution IV / Product Truth). Catalog already covers all five codes (`_shared/messages.ts`).

**Alternatives considered**: sanitizing-and-forwarding upstream text — rejected, any forwarded substring risks leak regression and tests would be brittle.

## D5 — Portal credential removal

**Decision**: Both harness clients lose service-role support (`test-apps/shared/supabase-client.js:59,71` custom-key path included). Superadmin flows authenticate as a seeded SUPER_ADMIN account through the anon client. Test-account passwords are generated at setup time by `run.ps1` and written to an untracked local file; nothing committable contains a password literal. Workflows with no unprivileged equivalent move to `docs/ops/runbook.md` manual steps.

**Rationale**: FR-006 zero-literals rule; verified test-apps already ships seeded accounts (`test-accounts.js`) so re-auth is mechanical. Note: `test_portal/` dies entirely (clarify Q1).

**Alternatives considered**: env-var-injected service key — rejected, still a privileged browser client pattern worth killing; keeping demo password123 for local-only — rejected, spec forbids literals regardless of reachability.

## D6 — Admin repository seam mirror

**Decision**: Per-feature `<f>_repository.dart` in `apps/admin/lib/features/<f>/`, typed methods returning `Either<Failure, T>` (reuse mobile's `core/either.dart`/`core/failure.dart` shapes), controllers consume repositories, screens consume controllers. All `dynamic _db` handles deleted. Widget tests keep passing with fakes injected at repository boundary.

**Rationale**: Mobile app proves the pattern in-repo (zero screen-level Supabase calls); AGENTS.md "Direct Repository Testing" becomes enforceable; 008 screens inherit deep seams.

**Alternatives considered**: single god repository — rejected, divergent change magnet; provider-level wrapping only — rejected, leaves call sites dynamic.

## D7 — Docs sync source of truth

**Decision**: Enumerations copied from shipped migrations, never invented: `slot_status = OPEN|CLOSED`, `waitlist_status = WAITING|OFFERED` (0058), `role = USER|ADMIN|SUPER_ADMIN` (0052, PRIEST removed 0060 → ADR-0002 pointer), plus outbox/payment enums verified against live types before writing. AGENTS.md admin-guard line updated to `ADMIN|SUPER_ADMIN`.

**Rationale**: Spec 009 FR-011 chose values-in-use deliberately; conventions doc predates and contradicts them. Sync direction is DB → docs, always.
