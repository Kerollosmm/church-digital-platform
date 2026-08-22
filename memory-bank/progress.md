# Progress & Status: Church Digital Platform

## Current Status Overview

| Component | Status | Test / Gate Outcome | Notes |
| :--- | :--- | :--- | :--- |
| **PostgreSQL Schema (0001-0065)** | **100% Passing** | 56/56 SQL suites registered | Ownership guard, `create_pending_payment`, `mark_payment_failed` |
| **Deno Edge Functions** | **100% Passing** | 100/100 tests PASS (100%) | `payments-gateway.ts` seam, zero-leak error contract |
| **Browser Test Harness (`test-apps/`)** | **100% Operational** | Served on `http://127.0.0.1:3000` | Re-auth via seeded role accounts, no literals |
| **Flutter Mobile App** | **100% Passing** | 23/23 suites PASS (82 tests), 0 lints | Deep repository seams, Arabic localization |
| **Flutter Web Admin App** | **100% Passing** | 23/23 suites PASS (50 tests), 0 lints | 8 typed repository seams, 0 direct DB queries in UI |
| **Feature 010 (Review Remediation)** | **Completed** | All 10 phases & 7 stories done | Commits: `9153c64`, `d7cb8da`, `7a827ac`, `8919b2d`, `af31f22`, `2a38f03`, `b74c449`, `f4d8307`, `cb4c89b`, `cd4e430`, `ef040bd`, `ccf3095` |

---

## What Works (Completed & Verified)

1. **Sacramental & Trip Slot Booking**:
   - Atomic reservation with `SELECT capacity FOR UPDATE` in `book_slot()`.
   - Realtime exhaustion broadcast (`SLOT_EXHAUSTED`).
   - Order-processing transition model (`PENDING_PAYMENT` -> `AWAITING_CALL` -> `CONFIRMED` -> `COMPLETED`).
2. **Unified Payments Seam (Feature 010 / US1)**:
   - Dedicated edge function gateway `_shared/payments-gateway.ts`.
   - Security-definer RPCs: `create_pending_payment`, `mark_payment_failed`, `record_booking_payment`, `apply_payment`.
   - Webhook HMAC SHA-512 verification, positive-int checks, and idempotent paid acknowledgement.
3. **Zero-Leak Error Contract (Feature 010 / US2)**:
   - Frozen error codes (`UNAUTHORIZED`, `FORBIDDEN`, `BAD_REQUEST`, `UPSTREAM_ERROR`, `INTERNAL`).
   - Catalog-driven Arabic message delivery with zero stack trace/internal exception leak.
4. **Clean Browser Test Harness (Feature 010 / US3, US7)**:
   - Single consolidated `test-apps/` harness with role-based authentication.
   - Elimination of `test_portal/` and committed credential literals.
5. **Admin Architecture & Typed Seams (Feature 010 / US4, US6)**:
   - Clean 3-step auth (Phone + OTP + PIN) without dead RPC calls.
   - Typed repositories across Content, Slots, Bookings, Complaints, Payments, Analytics.
   - Complete decoupling of UI widgets from database SDK transport.
6. **Encrypted Complaints System**:
   - PGCrypto encryption with Supabase Vault key (`submit_complaint_secure`).
   - Definer-rights view `v_complaints` and `decrypt_complaint()` RPC for authorized admins.
7. **Transactional Outbox & Notifications**:
   - `event_outbox` and `whatsapp_outbox` with `FOR UPDATE SKIP LOCKED` queue drain.
   - Stuck event reaper and retry backoff mechanism.

---

## What Is Left to Build (Next Milestone: Spec 008)

### Spec 008: Event Booking with Extra Services
- **Data Models**:
  - `event_types`: Marriage, Engagement, Baptism, Funerals with base prices.
  - `extra_services`: Photography, sound systems, chairs, decoration.
  - `event_type_extra_services`: Relationship mapping.
  - `booking_extra_services`: Price snapshot entries per reservation.
  - `venues_resources`: Hall/altar entities with `(resource_id, tstzrange)` exclusion constraints.
  - `payment_audit_logs`: Immutable ledger for cash receipts and adjustments.
- **Administrative RPCs**:
  - `admin_create_manual_booking`
  - `admin_confirm_booking` (allocates venue and locks schedule)
  - `admin_reject_booking` (captures mandatory rejection reason)
  - `admin_record_cash_payment` (audited cash recording)
