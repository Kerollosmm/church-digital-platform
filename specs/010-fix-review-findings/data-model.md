# Data Model: Review Findings Remediation

**Feature**: 010-fix-review-findings · **Date**: 2026-08-21

Remediation adds no new business tables and no new columns. Changes are privilege, call-path, code-shape, and documentation changes. This file records the entities whose *behavioral* surface moves.

## Entities

### payments (existing — write surface collapses)

- **Fields**: unchanged (`id`, `booking_id`, `amount`, `status`, `gateway_ref`, `raw_webhook`, …)
- **Write surface**: after remediation exactly one integration module may write; all writes execute inside SECURITY DEFINER RPCs
- **Status lifecycle**: unchanged — `CREATED → PAID | FAILED`; stale/cancelled race → `REFUND_PENDING` + refund request (existing semantics preserved)
- **Validation**: FR-001/FR-002 — no direct integration DML; non-owner advancement denied with zero rows

### bookings (existing — guard tightened)

- **State machine**: unchanged `PENDING_PAYMENT → AWAITING_CALL → CONFIRMED → COMPLETED` (+ CANCELLED/RESCHEDULED), guarded by existing trigger
- **Transition authorization** (changed): caller must be booking owner, admin-tier, or service role for EVERY action path — the apply-payment escape hatch is removed
- **Audit**: `audit_log` rows continue via existing trigger inside the RPC

### transition_booking_status (RPC — recreated by 0064)

- **Signature**: unchanged `(p_booking_id bigint, p_action text, p_new_status booking_status, …)`
- **Authorization rule (new)**: `is_admin() OR user_id = auth.uid() OR auth.role() = 'service_role'`
- **Privileges**: REVOKE ALL FROM PUBLIC, anon, authenticated → GRANT to authenticated, service_role

### error response body (contract — narrowed)

- **Shape**: `{ "error": CODE, "message_ar": "…" }` only
- **Codes**: frozen five, unchanged
- **Prohibited content**: library messages, exception text, upstream provider payloads (server-side structured logs are the only sink for detail)

### test-account credentials (tooling entity — relocated)

- **Before**: literals in committed JS
- **After**: generated at setup time by runner script, persisted to untracked local file; superadmin flows run as seeded SUPER_ADMIN over anon client

### documentation enumerations (projections)

- **Rule**: value-for-value equality with live DB types; retired values get a pointer to their removal decision (ADR-0002 / spec 009 US5); nothing invented

## State transitions

No new states. One authorization matrix change:

| Caller | Before (0063) | After (0064) |
|--------|---------------|--------------|
| Owner, any action | allowed except apply_payment escape misuse | allowed |
| Non-owner authenticated, `apply_payment` | **ALLOWED (bug)** | denied |
| ADMIN/SUPER_ADMIN | allowed | allowed |
| service_role | allowed (via escape) | allowed (explicit role check) |
