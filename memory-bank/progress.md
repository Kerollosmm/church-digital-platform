# Progress & Status: Church Digital Platform

## Current Status Overview

| Component | Status | Test / Gate Outcome | Notes |
| :--- | :--- | :--- | :--- |
| **PostgreSQL Schema (0001-0054)** | **100% Passing** | `db reset` clean + 46/46 SQL suites PASS | Security fixes, video dropped, 0054 template check |
| **Deno Edge Functions** | **100% Passing** | 84/84 unit tests PASS | `youtube-expiry` dropped; IDOR tests passing |
| **Flutter Mobile App** | **100% Passing** | 82/82 tests PASS, analyze clean | Video purchase screens purged |
| **Flutter Web Admin App** | **100% Passing** | 45/45 tests PASS, analyze clean | 3-step auth (Phone + OTP + PIN), videos removed |
| **Gate 6 (Auth Perimeter)** | **Verified Live** | Returns 401 with frozen Arabic JSON | Kong port 53321 verified |
| **Gate 7 (Staging E2E)** | **Blocked / Pending** | Requires staging Paymob secrets | Out-of-band credentials needed |
| **Git Repository** | **Pushed to Remote** | `origin/007-backend-security-fixes` | Ready for merge / PR review |

---

## What Works (Completed & Verified)

1. **Sacramental & Trip Slot Booking**:
   - Atomic reservation with `SELECT capacity FOR UPDATE`.
   - Realtime exhaustion broadcast (`SLOT_EXHAUSTED`).
   - Order-processing transition model (`PENDING_PAYMENT` -> `AWAITING_CALL` -> `CONFIRMED`).
2. **Hardened Payment Pipeline**:
   - Paymob webhook with constant-time HMAC SHA-512 verification.
   - `apply_payment` restricted to `service_role`.
   - Reconcile cron with non-failing transient error handling.
   - Stale lock refund handler (`REFUND_PENDING` + `refund_requests`).
3. **Outbox & Notification System**:
   - Atomic enqueue to `event_outbox`.
   - Concurrency-safe drain with `FOR UPDATE SKIP LOCKED`.
   - Stuck event reaper (`reap_stuck_outbox_events`) and admin resend view/RPC (`v_failed_outbox_events`).
   - Template check includes `admin_security_alert` (Migration 0054).
4. **Encrypted Complaints System**:
   - Asymmetric PGP/Vault encryption.
   - Definer-rights view `v_complaints` with strict `is_admin()` filter.
5. **Video Subsystem Decommissioning**:
   - 100% purged across database tables, RPCs, edge functions, cron jobs, mobile, and admin apps.
6. **TAP-Verified SQL Test Runner**:
   - `scripts/test-sql.js` & `scripts/sweep-sql.sh` automatically detect assertion failures inside `DO $$ ... $$` blocks over stdin.

---

## What Is Left to Build (Next Up: Spec 008)

### Spec 008: Event Booking Extra Services
- **Data Models**:
  - `event_types`: Marriage, Engagement, Baptism, Funerals with base prices.
  - `extra_services`: Photography, sound systems, chairs, decoration (with fixed vs quantity pricing).
  - `event_type_extra_services`: Many-to-many relationship mapping.
  - `booking_extra_services`: Price snapshot entries per reservation.
  - `venues_resources`: Hall/altar entities with `(resource_id, tstzrange)` exclusion constraints.
  - `payment_audit_logs`: Immutable ledger for cash receipts and adjustments.
- **Administrative RPCs**:
  - `admin_create_manual_booking`
  - `admin_confirm_booking` (allocates venue and locks schedule)
  - `admin_reject_booking` (captures mandatory rejection reason)
  - `admin_record_cash_payment` (audited cash recording)
  - `superadmin_*` configuration RPCs for event types and extra services.
- **WhatsApp Transactional Templates**:
  - Submission received, Booking confirmed, Booking rejected, Payment received / balance statement.
- **Flutter Clean Architecture Rework**:
  - Event reservation workflows on Mobile.
  - Event review, venue assignment, cash receipting, and failed outbox resend queues on Admin Web.
