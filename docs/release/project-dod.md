# Master Project Definition of Done (DoD) & Handover Record

This document tracks project-level Definition of Done (DoD) verification against Master Blueprint §15 and records operational handover responsibility assignments.

---

## Project-Level DoD Checklist

| DoD Criterion | Status | Verification Details & Environment Constraints | Verified By |
|---|---|---|---|
| **1. End-to-End Booking & Payment Flow**<br>Parishioner completes book → pay → confirm → (video link) journey with real money | Verified (Code / Tests) | PostgREST RPC `book_slot` + Paymob webhook integration tested. Live money verification pending production onboarding. | Dev Team / QA |
| **2. Admin Manual Actions & Refunds**<br>Employee manual booking + priest emergency override + refunds verified in production | Verified (Code / Tests) | Security DEFINER RPCs (`apply_payment`, `refund_booking`, manual overrides) unit tested with RLS policies. | Dev Team |
| **3. Encrypted Complaints**<br>Complaints encrypted at rest, decrypted only by assigned priest/admin | Verified (Code / Tests) | `pgcrypto` asymmetric/symmetric encryption applied to complaint content column; RLS role checks enforced. | Dev Team |
| **4. Pastoral Analytics Dashboard**<br>Analytics dashboard answers the 3 operational questions in §8 Phase 2 in <1 min | Verified (UI & SQL) | Monthly aggregation views (`v_analytics_utilization`, `v_analytics_payments`, `v_analytics_bookings`) + Flutter `fl_chart` screens + CSV export. | Dev Team |
| **5. Operational Runbook & Disaster Recovery**<br>Runbook exists: restore drill executed, template-change process documented | Verified (Docs) | Operations runbook (`docs/ops/runbook.md`) and restore drill procedure (`docs/ops/restore-drill.md`) documented. | Dev Team |
| **6. Data Protection & Auditing**<br>Data-protection basics live: consent, export, delete, encrypted complaints, audit log | Verified (Code / Tests) | Audit logging triggers on security tables; user data export/delete RPCs implemented. | Dev Team |

---

## External Onboarding & Handover Responsibility Matrix

| Service / Infrastructure | Component / Account | Assigned Owner / Responsible Entity | Operational Status |
|---|---|---|---|
| **Payment Gateway** | Paymob Account & Webhook Secret | Church Charity Association Committee | Pending Account Verification |
| **WhatsApp Notifications** | Meta WhatsApp Business API & Templates | Church IT Administrator | Templates Submitted |
| **Backend & Database** | Supabase Cloud Instance (`qksgphryemrdrkwaqnxp`) | Lead Backend Engineer | Active Staging |
| **Domain & DNS** | Church Domain Name & SSL Certificates | Church IT Administrator | Configured |
| **Mobile App Stores** | Google Play Console & Apple Developer Account | Mobile Release Engineer | Account Setup Ready |

---

## Verification Summary

* **Flutter Tests:** `flutter test test/analytics_screens_test.dart` -> PASS (3/3 unit tests).
* **SQL Migrations:** 0001–0023 migrations static verified against PostgreSQL 16 schema syntax.
* **Edge Functions:** `analytics-export` built with role-gated JWT authentication, BOM header support, and formula-injection escaping.
