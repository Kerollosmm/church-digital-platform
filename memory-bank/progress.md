# Progress & Status: Church Digital Platform

## Current Status Overview

| Component | Status | Test / Gate Outcome | Notes |
| :--- | :--- | :--- | :--- |
| **PostgreSQL Schema (0001-0078)** | **100% Passing** | 68 registered, 68 PASS, 0 FAIL | Migration 0078 schema verified; Suite 0078 fixture updated (`FIND-001` resolved) |
| **Deno Edge Functions** | **100% Passing** | 59/59 tests PASS (100%) | Edge functions, payments gateway `adminQuickCashCollect`, zero-leak contract |
| **Flutter Mobile App** | **100% Passing** | 94/94 tests PASS, 0 lints | Operational track branching (Sacrament vs Activity), documents checklist, Sunday School 📋 كشف الافتقاد modal |
| **Flutter Web Admin App** | **100% Passing** | 81/81 tests PASS, 0 lints | AdminCashierScreen, fast search, 1-click cash collect, sacramental vs activity queue tabs |
| **Operational Pivot (3 Tracks)** | **Completed** | Verified | Sacramental intake, Activities/trips add-ons, Sunday School pastoral visitation & cash cashier |

---

## What Works (Completed & Verified)

1. **Church Platform Operational Pivot (3 Operational Tracks)**:
   - **Track 1 (Sacraments)**: Pure pastoral intake workflow for Weddings, Baptisms, Funerals, and Betrothals. Required documents checklist card (`required_documents_ar`), submission for ecclesiastical review (`إرسال طلب الحجز للمراجعة الكنسية`), zero commercial add-ons.
   - **Track 2 (Activities & Trips)**: Interactive extra services selection (meals, transportation, supplies), dynamic totalizer, wallet / cash collection.
   - **Track 3 (Sunday School Visitation)**: 1-click attendance marking + 1-click **[📋 كشف الافتقاد]** visitation bottom sheet with student contacts, parent phone, consecutive absences tracking, and direct WhatsApp / Call actions.
   - **Secretariat Cashier & Fast Collection**: `AdminCashierScreen` and `admin_quick_cash_collect` RPC for fast phone search and instant cash receipting with atomic audit trail and WhatsApp outbox triggers.
2. **Spec 008: Event Booking with Extra Services (ADR 0002)**:
   - Separate domain entities: `event_types`, `extra_services`, `event_type_extra_services`, `venues_resources`, `event_bookings`, `booking_extra_services`, `payment_audit_logs`.
   - GiST temporal range exclusion constraint on `(assigned_venue_id, booking_range)` preventing venue double-booking.
   - Price snapshotting in integer piastres on line items (`booking_extra_services`).
   - Atomic state machine RPCs: `submit_event_booking`, `admin_confirm_booking`, `admin_reject_booking`, `admin_record_cash_payment`, `admin_quick_cash_collect`.

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
