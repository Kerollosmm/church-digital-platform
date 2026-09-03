# Active Context: Church Digital Platform

## Current Focus & Status
- **Current Milestone**: Testing Improvements (TEST-01 – TEST-04) — **Completed & Verified**.
- **Forensic Review Status**:
  - Test suites verification:
    - PostgreSQL Schema: Migrations 0001–0080 replayed cleanly. 70/70 test suites pass individually (100%).
    - Deno Edge Functions: 73/73 tests PASS (plus 5 diagnostic engine tests = 78 tests total) (`deno test --allow-env --allow-net supabase/functions/`).
    - Flutter Mobile: 88/88 tests PASS, 0 analyzer issues (`apps/mobile/`).
    - Flutter Admin: 80/80 tests PASS, 0 analyzer issues (`apps/admin/`).
- **Performance Optimizations (OPT-01 – OPT-04) Completed**:
  - **OPT-01**: `test-apps/user/app.js:195` DOM NodeList caching outside tab click event loop (164.86x measured speedup).
  - **OPT-02**: `test-apps/superadmin/app.js:313` direct `for...of` loop over `authData.users` replacing `forEach`.
  - **OPT-03**: `supabase/functions/event-dispatcher/index.ts:302` bulk status update using `.in('id', batchIds)` in 1 PostgREST roundtrip (10x roundtrip reduction) + `.in()` support on `FakeQuery` in `_shared/fake_supabase.ts`.
  - **OPT-04**: `test-apps/user/app.js:654` Map lookup `state.slotsById.get(slotId)` with fallback to `find()` (18.36x measured speedup).
- **Next Immediate Step**:
  1. Stage and commit verified updates.

---

## Recent Commits / Changes
- **Testing Improvements (TEST-01 – TEST-04)**:
  - *OTP-SMS Webhook Error Handling*: Added malformed payload test in `supabase/functions/otp-sms/index_test.ts` verifying 401 UNAUTHORIZED on corrupted payload without leaking details.
  - *VerifyCronOrServiceAuth Coverage*: Added comprehensive 6-scenario test suite in `supabase/functions/_tests/http_test.ts` covering Bearer cronSecret, x-cron-secret header, Bearer serviceRoleKey, missing auth (401), invalid token (401), and unconfigured secrets (500).
  - *FCM OAuth2 Error Handling*: Added 2 error tests in `supabase/functions/event-dispatcher/index_test.ts` verifying that OAuth2 HTTP errors (401) and network fetch exceptions properly return null and mark the outbox row as FAILED.
  - *Diagnostic Engine Unit Test Suite*: Added `diagnostic_engine/engine_test.ts` with 5 automated unit tests covering `BrainAgent.synthesizeVectors`, `AuditorAgent.audit` (RLS violations, empty arrays, perimeter bypass), and `AuditorAgent.generateReport`. Guarded `run()` execution in `diagnostic_engine/engine.ts` on module import.
- **Code Health Improvements (CLEAN-01 – CLEAN-05)**:
  - *Android Signing Config & App ID*: Verified `apps/mobile/android/app/build.gradle.kts` already clean with canonical `applicationId = "eg.church.mobile"`, dynamic `key.properties` signing config, and zero TODO comments.
  - *Deprecated Theme Member*: Removed deprecated `surfaceVariant: AppColors.surfaceVariant` and `// ignore: deprecated_member_use` from `apps/mobile/lib/theme/app_theme.dart` in favor of standard `surfaceContainerHighest`.
  - *Leftover Test Print*: Removed leftover debug `print` block with `// ignore: avoid_print` from `apps/admin/test/features/payments/payouts_config_test.dart`.
  - *Modern Web Download*: Refactored `apps/admin/lib/features/analytics/web_download.dart` to use modern `package:web` and `dart:js_interop` instead of deprecated `dart:html`, eliminating `ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use`; updated conditional import in `export_report_button.dart` to `dart.library.js_interop`; declared `web: ^1.1.1` in `apps/admin/pubspec.yaml`.
  - *Zero Analyzer Warnings*: Verified `flutter analyze apps/admin apps/mobile` passes with 0 issues; 88/88 mobile tests and 80/80 admin tests PASS.
- **Security Hardening & SAST Remediation (SEC-01, SEC-02, SEC-03)**:
  - Fixed overly permissive CORS policy in `supabase/functions/_shared/http.ts` by replacing `*` with request-aware origin matching (`getAllowedOrigins`, `isAllowedOrigin`, `getCorsHeaders`), `Vary: Origin`, and configurable `ALLOWED_ORIGINS` / `ALLOWED_ORIGIN`.
  - Added CORS unit tests in `supabase/functions/_tests/http_test.ts` verifying safe default, allowed origin reflection, preflight OPTIONS, and rejected origins (64/64 Deno tests passing).
  - Sanitized dynamic SQL sequence grants in `supabase/migrations/0042_social_links.sql:41` and `supabase/migrations/0043_faq_categories.sql:86` using `EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %s TO authenticated', v_seq::regclass);`.
- **Performance Optimizations Completed**:
  - **OPT-01**: `test-apps/user/app.js:195` DOM NodeList caching outside tab click event loop (164.86x measured speedup).
  - **OPT-02**: `test-apps/superadmin/app.js:313` direct `for...of` loop over `authData.users` replacing `forEach`.
  - **OPT-03**: `supabase/functions/event-dispatcher/index.ts:302` bulk status update using `.in('id', batchIds)` in 1 PostgREST roundtrip (10x roundtrip reduction) + `.in()` support on `FakeQuery` in `_shared/fake_supabase.ts`.
  - **OPT-04**: `test-apps/user/app.js:654` Map lookup `state.slotsById.get(slotId)` with fallback to `find()` (18.36x measured speedup).
- **Sunday School & Attendance Decommissioning + Flutter Mobile Build Config Hardening (`refactor/church-operational-pivot`)**:
  - *Android Release Signing*: `apps/mobile/android/app/build.gradle.kts` dynamically loads `key.properties` when present, configures `release` signing config, and falls back to `debug` signing without failing CI/local runs.
  - *Android Application ID*: Retained unique identifier `eg.church.mobile` and cleaned stale TODO placeholder.
  - *Credential Security Guard*: Added `key.properties.example` template and hardened `apps/mobile/.gitignore` against `key.properties`, `*.keystore`, and `*.jks`.
  - *CMakeLists Ephemeral Invariant*: Verified that Linux/Windows `CMakeLists.txt` TODOs are upstream Flutter SDK issue #57146 that must remain untouched per engine warnings.
  - *Database Forward Migration*: `0080_drop_sunday_school_stack.sql` cleanly drops RPCs (`get_class_visitation_list`, `record_bulk_attendance`, `is_class_servant`) and tables (`sunday_school_attendance`, `sunday_school_sessions`, `sunday_school_students`, `sunday_school_servants`, `sunday_school_classes`) CASCADE.
  - *Client Directories Purged*: `apps/mobile/lib/features/sunday_school/` and `apps/admin/lib/features/sunday_school/` deleted along with their test suites.
  - *Zero Orphan Invariant Verified*: Zero references remaining in mobile or admin app routers or widgets.

---


## Architecture & Lifecycle: Manual Payment Verification (ADR 0003)

### Payment Lifecycle Flow
```
[Member Books Slot]
        ↓
  `book_slot()` RPC (status: PENDING_PAYMENT, locked_until: +20m)
        ↓
[Member Views Payout Channels (`payout_channels`)]
        ↓
[Member Submits Proof + Screenshot]
        ↓
  `submit_payment_proof()` RPC (creates `payment_proofs` row in PENDING, stays PENDING_PAYMENT)
        ↓
[Admin Reviews in Review Queue (`v_payment_review_queue`)]
        ├── [Admin Rejects] → `reject_payment_proof()` (status: REJECTED, reason logged) → Member may resubmit
        ↓
  [Admin Approves] → `approve_payment_proof()` RPC
        ↓
  `apply_payment()` invoked
        ↓
  `payments.status = 'PAID'`
  `bookings.status = 'AWAITING_CALL'`
  `event_outbox` enqueues WhatsApp `booking_payment_received`
        ↓
[Admin Calls & Confirms] → `transition_booking_status('CONFIRMED')`
```

---

## Deliverables & Accomplishments (Feature 011)

### 1. User Story 1 (P1): Member Payment Proof Submission
- **Migrations 0066 & 0067**:
  - Created `payout_channels` table and `payment_proofs` table with RLS and storage bucket `payment-proofs`.
  - Created `submit_payment_proof(p_booking_id, p_channel, p_sender_phone, p_reference_number, p_amount_claimed, p_image_path)` RPC.
- **Mobile Client**:
  - `PaymentProofScreen` with dynamic payout details, validation, image upload, and Arabic error feedback.
  - `BookingRepository` methods: `fetchPayoutChannels`, `submitPaymentProof`, `uploadProofImage`.

### 2. User Story 2 (P1): Staff Decision Engine & Review Queue
- **Migration 0068**:
  - Created `v_payment_review_queue` view.
  - Created `approve_payment_proof(p_proof_id, p_collector_note)` and `reject_payment_proof(p_proof_id, p_reason_code)` RPCs with `FOR UPDATE` lock and audit logging.
- **Admin Portal**:
  - `PaymentReviewQueueScreen` with receipt preview, inline approval modal, and rejection catalog reason selection.
  - `PaymentsAdminRepository` methods: `listPendingProofs`, `approveProof`, `rejectProof`.

### 3. User Story 3 (P2): Direct In-Person Cash Collection
- **Migration 0069**:
  - Created `mark_cash_received(p_booking_id, p_amount, p_collector_note)` RPC for on-the-spot cash payments.
- **Admin Portal**:
  - `CashReceivedSheet` bottom sheet with amount validation and collector notes.

### 4. User Story 4 (P2): Church Payout Channels Configuration
- **Migration 0066**:
  - `payout_channels` with SUPER_ADMIN write RLS and public read.
- **Admin Portal**:
  - `PayoutsConfigScreen` enabling SUPER_ADMIN configuration of Vodafone Cash and InstaPay endpoints.

### 5. User Story 5 (P1): Decommissioning of Paymob Stack
- **Migration 0070**:
  - Dropped `record_webhook_payment` and `mark_payment_failed` RPCs.
  - Dropped `payments.raw_webhook` column and purged `PAYMOB_REFUND` outbox rows.
  - Unscheduled `reconcile-payments` pg_cron job.
- **Codebase Sweep**:
  - Deleted `paymob-checkout/`, `paymob-webhook/`, `reconcile-payments/`, `paymob.ts`.
  - Deleted `booking_checkout_session.dart` and `payment_redirect_screen.dart`.
  - Zero `paymob` references remaining across backend, mobile, and admin apps.

### 6. User Story 6 (P3): Notification Wiring
- Verified WhatsApp `booking_payment_received` template dispatch on proof approval via `event-dispatcher`.
