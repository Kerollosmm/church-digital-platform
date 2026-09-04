# Progress & Status: Church Digital Platform

## Current Status Overview

| Component | Status | Test / Gate Outcome | Notes |
| :--- | :--- | :--- | :--- |
| **PostgreSQL Schema (0001-0080)** | **100% Passing** | 70 registered, 70 PASS, 0 FAIL | Migration 0080 dropped Sunday School tables/RPCs |
| **Deno Edge Functions** | **100% Passing** | 75/75 tests PASS (100%) + 5/5 Diagnostic Engine tests PASS | Edge functions, payments gateway `adminQuickCashCollect`, zero-leak contract, CORS origin validation, TEST-01–04 suites, CLEAN-07–09 runner log cleanup, SEC-OUTBOX-THROW handler isolation + `FakeQuery.eq` fake repair |
| **Flutter Mobile App** | **100% Passing** | 88/88 tests PASS, 0 lints | Sunday School feature removed cleanly, 0 analyzer issues, SEC-OTP-PII verified, CLEAN-06 LoginScreen decomposition |
| **Flutter Web Admin App** | **100% Passing** | 80/80 tests PASS, 0 lints | Sunday School feature removed cleanly, 0 analyzer issues, SEC-OTP-PII verified |
| **Security & PII Hardening** | **100% Remediated** | SEC-OTP-PII verified (CWE-532 mitigation) | Plain text phone number PII redacted from client debugPrint calls |
| **Code Health & Quality** | **100% Passing** | CLEAN-01 – CLEAN-16 verified | Build method decompositions (LoginScreen, BookingDetailScreen, OtpScreen, FamilyCertificatesScreen), script/diagnostic log cleanup, 0 analyzer warnings |
| **Operational Tracks** | **Cleaned & Active** | Sacraments & Activities active | Sunday School decommissioned per owner decision |

---

## Deliverables Completed

### SEC-OUTBOX-THROW: Event-Dispatcher Handler Throw Isolation (2026-09-04)
- **Handler Throw Isolation**: Wrapped `await handler(row as Row, deps)` in `supabase/functions/event-dispatcher/index.ts` batch loop with try/catch → `{ ok: false, retryable: true, error }`. Eliminates duplicate WhatsApp/FCM send blasts caused by one row's network exception rejecting `Promise.all`, orphaning batch status writes, and letting the 5-minute `reap_stuck_outbox_events` cron re-dispatch already-sent messages.
- **Regression Coverage**: Added throw-isolation test (HTTP 200 + retryable PENDING) and mixed-batch split-write test (SENT bulk `.in()` + individual FAILED/PENDING updates). Dispatcher suite 8/8.
- **Test-Fake Repair**: Fixed `FakeQuery.eq` in `supabase/functions/_shared/fake_supabase.ts` — `.update().eq()` mutated all table rows before filtering; now filters first (mirrors `.in()`). Full edge suite 75/75.

### CLEAN-10 – CLEAN-16: Code Health Improvements
- **BookingDetailScreen Build Method Decomposition (CLEAN-10)**: Refactored `apps/mobile/lib/features/booking/booking_detail_screen.dart` monolithic `build()` method (226 lines) into modular private widgets: `_CountdownBanner`, `_SummaryCard`, `_WhatsappOptInCard`, `_BottomActionSheet`. All tests pass; 0 analyzer issues.
- **OtpScreen Build Method Decomposition (CLEAN-11)**: Refactored `apps/mobile/lib/features/auth/otp_screen.dart` monolithic `build()` method (268 lines) into clean private widgets: `_BackgroundDecorations`, `_OtpHeader`, `_OtpInputRow`, `_OtpResendRow`, `_FooterLinks`. All tests pass; 0 analyzer issues.
- **FamilyCertificatesScreen Build Method Decomposition (CLEAN-12)**: Refactored `apps/mobile/lib/features/family_archive/family_certificates_screen.dart` monolithic `build()` method (196 lines) into clean private widgets: `_ErrorView`, `_EmptyCertificatesView`, `_CertificateCard`. 0 analyzer issues.
- **Diagnostic & Script Console Log Cleanup (CLEAN-13 – CLEAN-16)**: Removed leftover `console.log` statements in `diagnostic_engine/deno_engine.ts:99`, `diagnostic_engine/test_real_all_features.ts:10`, `diagnostic_engine/engine.ts:101`, and `scripts/test-sql.js:14`. Verified with `deno test`, `deno run`, and `node --check`.

### CLEAN-06 – CLEAN-09: Code Health Improvements
- **LoginScreen Build Method Decomposition (CLEAN-06)**: Refactored `apps/mobile/lib/features/auth/login_screen.dart` overly long monolithic `build()` method (282 lines) into clean, composable private sub-widgets: `_BackgroundDecorations`, `_LoginHeader`, `_CountryCodePrefix`, `_PhoneInputField`, `_SubmitButton`, `_FooterLinks`. Preserved all RTL directionality, phone input formatters, validator rules, and UI aesthetics. All 4 widget tests pass; 0 analyzer issues.
- **Diagnostic Engine Console Log Cleanup (CLEAN-07 – CLEAN-09)**: Removed leftover ASCII banner `console.log` statements at the entry points of `diagnostic_engine/test_real_high_concurrency.ts:10`, `diagnostic_engine/test_real_analytics_export.ts:5`, and `diagnostic_engine/test_real_event_dispatcher.ts:10`. All verification runners continue to pass cleanly with exit code 0.

### SEC-OTP-PII: OTP Phone PII Redaction in Client Logs
- **Vulnerability**: CWE-532 (Insertion of Sensitive Information into Log File) via plain text phone number interpolation in `debugPrint` calls.
- **Implementation**:
  - `apps/mobile/lib/core/auth/phone_verify_gate.dart`: Redacted raw phone numbers from error `debugPrint` statements during OTP send (line 164), verify (line 193), and resend (line 207).
  - `apps/admin/lib/features/auth/otp_screen.dart`: Redacted raw phone number from error `debugPrint` statement during OTP verification (line 40).
- **Security Impact**: Ensures user phone numbers are never leaked to device system logs (logcat, syslog, browser console) during OTP failures.
- **Verification**: Mobile: 88/88 tests PASS, Admin: 80/80 tests PASS, 0 analyzer issues across both apps.

---

## What Works (Completed & Verified)

1. **Testing Improvements & Hardening (TEST-01 – TEST-04)**:
   - *OTP-SMS Webhook Error Handling*: Added malformed payload test in `supabase/functions/otp-sms/index_test.ts` verifying 401 UNAUTHORIZED on corrupted payload without leaking details.
   - *VerifyCronOrServiceAuth Coverage*: Added comprehensive 6-scenario test suite in `supabase/functions/_tests/http_test.ts` covering Bearer cronSecret, x-cron-secret header, Bearer serviceRoleKey, missing auth (401), invalid token (401), and unconfigured secrets (500).
   - *FCM OAuth2 Error Handling*: Added 2 error tests in `supabase/functions/event-dispatcher/index_test.ts` verifying that OAuth2 HTTP errors (401) and network fetch exceptions properly return null and mark the outbox row as FAILED.
   - *Diagnostic Engine Unit Test Suite*: Added `diagnostic_engine/engine_test.ts` with 5 automated unit tests covering `BrainAgent.synthesizeVectors`, `AuditorAgent.audit` (RLS violations, empty arrays, perimeter bypass), and `AuditorAgent.generateReport`. Guarded `run()` execution in `diagnostic_engine/engine.ts` on module import.
2. **Security Hardening & SAST Remediation (CORS & SQL format)**:
   - Fixed overly permissive CORS policy in `supabase/functions/_shared/http.ts` replacing `*` with request-aware origin matching (`getAllowedOrigins`, `isAllowedOrigin`, `getCorsHeaders`), `Vary: Origin`, and configurable `ALLOWED_ORIGINS` / `ALLOWED_ORIGIN`.
   - Added comprehensive CORS unit tests in `supabase/functions/_tests/http_test.ts` verifying safe default, allowed origin reflection, preflight OPTIONS, and rejected origins (64/64 Deno tests PASS).
   - Sanitized dynamic SQL sequence grants in `supabase/migrations/0042_social_links.sql:41` and `supabase/migrations/0043_faq_categories.sql:86` using `EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %s TO authenticated', v_seq::regclass);`.
3. **Performance Optimizations (OPT-01 – OPT-04)**:
   - **OPT-01**: `test-apps/user/app.js:195` DOM NodeList caching outside tab click event loop (164.86x measured speedup).
   - **OPT-02**: `test-apps/superadmin/app.js:313` declarative `Object.fromEntries(authData.users.map(au => [au.id, au]))` replacing imperative `for...of` mutation for `authUsersMap`.
   - **OPT-03**: `supabase/functions/event-dispatcher/index.ts:310` decoupled handler execution from DB writes in `batch.map`, aggregating all `SENT` status updates into 1 bulk `.in('id', sentIds)` call per batch (81.82% DB roundtrip reduction: 110 -> 20 calls; 6.64x speedup).
   - **OPT-04**: `test-apps/user/app.js:654` Map lookup `state.slotsById.get(slotId)` with fallback to `find()` (18.36x measured speedup).
4. **Flutter Mobile Build & Release Hardening**:
   - Dynamic release signing configured in `apps/mobile/android/app/build.gradle.kts` via `key.properties` with fallback to `debug` signing.
   - `applicationId = "eg.church.mobile"` verified as canonical unique package ID; stale TODO placeholder removed.
   - Credentials protected: `apps/mobile/android/key.properties.example` added; `apps/mobile/.gitignore` hardened against keystore files.
   - Linux and Windows `CMakeLists.txt` ephemeral files TODO identified as upstream Flutter SDK issue #57146; left untouched per `# This file controls Flutter-level build steps. It should not be edited.` invariant.
   - 88/88 mobile tests PASS; 0 analyzer issues.
5. **Church Platform Operational Pivot (3 Operational Tracks)**:
   - **Track 1 (Sacraments)**: Pure pastoral intake workflow for Weddings, Baptisms, Funerals, and Betrothals. Required documents checklist card (`required_documents_ar`), submission for ecclesiastical review (`إرسال طلب الحجز للمراجعة الكنسية`), zero commercial add-ons.
   - **Track 2 (Activities & Trips)**: Interactive extra services selection (meals, transportation, supplies), dynamic totalizer, wallet / cash collection.
   - **Track 3 (Sunday School Visitation)**: 1-click attendance marking + 1-click **[📋 كشف الافتقاد]** visitation bottom sheet with student contacts, parent phone, consecutive absences tracking, and direct WhatsApp / Call actions.
   - **Secretariat Cashier & Fast Collection**: `AdminCashierScreen` and `admin_quick_cash_collect` RPC for fast phone search and instant cash receipting with atomic audit trail and WhatsApp outbox triggers.
6. **Spec 008: Event Booking with Extra Services (ADR 0002)**:
   - Separate domain entities: `event_types`, `extra_services`, `event_type_extra_services`, `venues_resources`, `event_bookings`, `booking_extra_services`, `payment_audit_logs`.
   - GiST temporal range exclusion constraint on `(assigned_venue_id, booking_range)` preventing venue double-booking.
   - Price snapshotting in integer piastres on line items (`booking_extra_services`).
   - Atomic state machine RPCs: `submit_event_booking`, `admin_confirm_booking`, `admin_reject_booking`, `admin_record_cash_payment`, `admin_quick_cash_collect`.
   - Transactional WhatsApp outbox template integration (`event_booking_submitted`, `event_booking_confirmed`, `event_booking_rejected`, `event_booking_payment_received`).
   - Flutter Mobile screen `EventBookingScreen` with interactive extra services selection and live EGP totalizer.
   - Flutter Admin Web screen `EventBookingsAdminScreen` with queue tabs, venue assignment dialog, and cash collection sheet.
7. **Manual Payment Verification Rail (Feature 011 / ADR 0003)**:
   - Dynamic payout channel configuration for Vodafone Cash, InstaPay, Cash.
   - Member payment proof upload to Supabase Storage (`payment-proofs`) and submission RPC (`submit_payment_proof`).
   - Staff review queue with receipt preview, approval modal, and rejection reason tracking.
   - Cash receipt recording via `mark_cash_received` RPC.
   - Complete decommissioning of Paymob gateway endpoints, webhooks, crons, and client files.
8. **Zero-Leak Error Contract & Security Hardening**:
   - Frozen error codes (`UNAUTHORIZED`, `FORBIDDEN`, `BAD_REQUEST`, `UPSTREAM_ERROR`, `INTERNAL`).
   - Catalog-driven Arabic message delivery with zero stack trace/internal exception leak.
   - Revocation of direct client DML on sensitive tables (`event_bookings`, `payments`, `payment_audit_logs`).
9. **Code Health Improvements (CLEAN-01 – CLEAN-05)**:
   - *Android Signing Config & App ID*: Verified `apps/mobile/android/app/build.gradle.kts` already clean with canonical `applicationId = "eg.church.mobile"`, dynamic `key.properties` signing config, and zero TODO comments.
   - *Deprecated Theme Member*: Removed deprecated `surfaceVariant: AppColors.surfaceVariant` and `// ignore: deprecated_member_use` from `apps/mobile/lib/theme/app_theme.dart` in favor of standard `surfaceContainerHighest`.
   - *Leftover Test Print*: Removed leftover debug `print` block with `// ignore: avoid_print` from `apps/admin/test/features/payments/payouts_config_test.dart`.
   - *Modern Web Download*: Refactored `apps/admin/lib/features/analytics/web_download.dart` to use modern `package:web` and `dart:js_interop` instead of deprecated `dart:html`, eliminating `ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use`; updated conditional import in `export_report_button.dart` to `dart.library.js_interop`; declared `web: ^1.1.1` in `apps/admin/pubspec.yaml`.
   - *Zero Analyzer Warnings*: Verified `flutter analyze apps/admin apps/mobile` passes with 0 issues; 88/88 mobile tests and 80/80 admin tests PASS.
10. **Code Health Improvements (CLEAN-06 – CLEAN-09)**:
    - *LoginScreen Build Method Decomposition*: Refactored `apps/mobile/lib/features/auth/login_screen.dart` overly long monolithic `build()` method (282 lines) into clean, composable private sub-widgets: `_BackgroundDecorations`, `_LoginHeader`, `_CountryCodePrefix`, `_PhoneInputField`, `_SubmitButton`, `_FooterLinks`. Preserved all RTL directionality, phone input formatters, validator rules, and UI aesthetics. All 4 widget tests pass; 0 analyzer issues.
    - *Diagnostic Engine Console Log Cleanup*: Removed leftover ASCII banner `console.log` statements at the entry points of `diagnostic_engine/test_real_high_concurrency.ts:10`, `diagnostic_engine/test_real_analytics_export.ts:5`, and `diagnostic_engine/test_real_event_dispatcher.ts:10`. All verification runners continue to pass cleanly with exit code 0.
11. **Code Health Improvements (CLEAN-10 – CLEAN-16)**:
    - *BookingDetailScreen Build Method Decomposition (CLEAN-10)*: Refactored `apps/mobile/lib/features/booking/booking_detail_screen.dart` monolithic `build()` method (226 lines) into modular private widgets: `_CountdownBanner`, `_SummaryCard`, `_WhatsappOptInCard`, `_BottomActionSheet`. All tests pass; 0 analyzer issues.
    - *OtpScreen Build Method Decomposition (CLEAN-11)*: Refactored `apps/mobile/lib/features/auth/otp_screen.dart` monolithic `build()` method (268 lines) into clean private widgets: `_BackgroundDecorations`, `_OtpHeader`, `_OtpInputRow`, `_OtpResendRow`, `_FooterLinks`. All tests pass; 0 analyzer issues.
    - *FamilyCertificatesScreen Build Method Decomposition (CLEAN-12)*: Refactored `apps/mobile/lib/features/family_archive/family_certificates_screen.dart` monolithic `build()` method (196 lines) into clean private widgets: `_ErrorView`, `_EmptyCertificatesView`, `_CertificateCard`. 0 analyzer issues.
    - *Diagnostic & Script Console Log Cleanup (CLEAN-13 – CLEAN-16)*: Removed leftover `console.log` statements in `diagnostic_engine/deno_engine.ts:99`, `diagnostic_engine/test_real_all_features.ts:10`, `diagnostic_engine/engine.ts:101`, and `scripts/test-sql.js:14`. Verified with `deno test`, `deno run`, and `node --check`.

---

## What Is Left to Build
- Production deployment and staging smoke tests.
