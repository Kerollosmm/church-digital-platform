# Progress & Status: Church Digital Platform

## Current Status Overview

| Component | Status | Test / Gate Outcome | Notes |
| :--- | :--- | :--- | :--- |
| **PostgreSQL Schema (0001-0074)** | **100% Passing** | 64/64 SQL suites registered | Migrations 0073–0074: Event booking schema, GiST exclusion, price snapshots, RPCs |
| **Deno Edge Functions** | **100% Passing** | 58/58 tests PASS (100%) | 5 edge functions, payments gateway RPC wrapper, zero-leak contract |
| **Flutter Mobile App** | **100% Passing** | 81/81 tests PASS, 0 lints | EventBookingScreen, SupabaseEventBookingRepository, price calculation, Arabic UI |
| **Flutter Web Admin App** | **100% Passing** | 65/65 tests PASS, 0 lints | EventBookingsAdminScreen, SupabaseEventBookingsAdminRepository, venue dialogs |
| **Feature 008 (Event Booking)** | **Completed** | 100% Verified | Database schema, GiST range exclusion, state machine RPCs, mobile & admin apps |

---

## What Works (Completed & Verified)

1. **Spec 008: Event Booking with Extra Services (ADR 0002)**:
   - Separate domain entities: `event_types`, `extra_services`, `event_type_extra_services`, `venues_resources`, `event_bookings`, `booking_extra_services`, `payment_audit_logs`.
   - GiST temporal range exclusion constraint on `(assigned_venue_id, booking_range)` preventing venue double-booking.
   - Price snapshotting in integer piastres on line items (`booking_extra_services`).
   - Atomic state machine RPCs: `submit_event_booking`, `admin_confirm_booking`, `admin_reject_booking`, `admin_record_cash_payment`, `admin_create_manual_booking`.
   - Transactional WhatsApp outbox template integration (`event_booking_submitted`, `event_booking_confirmed`, `event_booking_rejected`, `event_booking_payment_received`).
   - Flutter Mobile screen `EventBookingScreen` with interactive extra services selection and live EGP totalizer.
   - Flutter Admin Web screen `EventBookingsAdminScreen` with queue tabs, venue assignment dialog, and cash collection sheet.
2. **Manual Payment Verification Rail (Feature 011 / ADR 0003)**:
   - Dynamic payout channel configuration for Vodafone Cash, InstaPay, Cash.
   - Member payment proof upload to Supabase Storage (`payment-proofs`) and submission RPC (`submit_payment_proof`).
   - Staff review queue with receipt preview, approval modal, and rejection reason tracking.
   - Cash receipt recording via `mark_cash_received` RPC.
   - Complete decommissioning of Paymob gateway endpoints, webhooks, crons, and client files.
3. **Zero-Leak Error Contract & Security Hardening**:
   - Frozen error codes (`UNAUTHORIZED`, `FORBIDDEN`, `BAD_REQUEST`, `UPSTREAM_ERROR`, `INTERNAL`).
   - Catalog-driven Arabic message delivery with zero stack trace/internal exception leak.
   - Revocation of direct client DML on sensitive tables (`event_bookings`, `payments`, `payment_audit_logs`).

---

## What Is Left to Build
- Production deployment and staging smoke tests.
