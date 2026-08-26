# Progress & Status: Church Digital Platform

## Current Status Overview

| Component | Status | Test / Gate Outcome | Notes |
| :--- | :--- | :--- | :--- |
| **PostgreSQL Schema (0001-0072)** | **100% Passing** | 62/62 SQL suites registered | Migrations 0066–0072: Manual payments, proof review, Paymob drop, security hardening |
| **Deno Edge Functions** | **100% Passing** | 63/63 tests PASS (100%) | 5 edge functions, payments gateway RPC wrapper, zero-leak contract |
| **Flutter Mobile App** | **100% Passing** | 80/80 tests PASS, 0 lints | PaymentProofScreen, direct booking reservation, Arabic UI, hardened catch blocks |
| **Flutter Web Admin App** | **100% Passing** | 64/64 tests PASS, 0 lints | PaymentReviewQueue, CashReceivedSheet, PayoutsConfigScreen, error logging |
| **Feature 011 (Manual Payments)** | **Completed** | All 9 phases & 6 stories done | Commits: `09b5cd3`, `c357eb2`, `8880d5d`, `14c92f4`, `5916ba7`, `1114cc6`, `f2951b0`, `becb266`, `710daa1` |
| **Code Health Hardening** | **Completed** | Error logging + dead code audit | Resolved empty catch blocks across mobile/admin, validated test fixtures |

---

## What Works (Completed & Verified)

1. **Sacramental & Event Slot Booking**:
   - Atomic reservation with `SELECT capacity FOR UPDATE` in `book_slot()`.
   - Realtime exhaustion broadcast (`SLOT_EXHAUSTED`).
   - Order-processing transition model (`PENDING_PAYMENT` -> `AWAITING_CALL` -> `CONFIRMED` -> `COMPLETED`).
2. **Manual Payment Verification Rail (Feature 011 / ADR 0003)**:
   - Dynamic payout channel configuration for Vodafone Cash, InstaPay, Cash.
   - Member payment proof upload to Supabase Storage (`payment-proofs`) and submission RPC (`submit_payment_proof`).
   - Staff review queue with receipt preview, approval modal, and rejection reason tracking.
   - Cash receipt recording via `mark_cash_received` RPC.
   - Complete decommissioning of Paymob gateway endpoints, webhooks, crons, and client files.
3. **Zero-Leak Error Contract**:
   - Frozen error codes (`UNAUTHORIZED`, `FORBIDDEN`, `BAD_REQUEST`, `UPSTREAM_ERROR`, `INTERNAL`).
   - Catalog-driven Arabic message delivery with zero stack trace/internal exception leak.
4. **Admin Architecture & Typed Seams**:
   - Clean 3-step auth (Phone + OTP + PIN) with RBAC (`ADMIN`, `SUPER_ADMIN`).
   - Typed repositories across Content, Slots, Bookings, Complaints, Payments, Analytics.
5. **Encrypted Complaints System**:
   - PGCrypto encryption with Supabase Vault key (`submit_complaint_secure`).
   - Definer-rights view `v_complaints` and `decrypt_complaint()` RPC for authorized admins.
6. **Transactional Outbox & Notifications**:
   - `event_outbox` with `FOR UPDATE SKIP LOCKED` queue drain.
   - WhatsApp template triggers (`booking_payment_received`, `booking_confirmed`, etc.) and FCM push notifications.

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
