# Active Context: Church Digital Platform

## Current Focus & Status
- **Current Milestone**: Staging Deployment & Smoke Tests (2026-09-05) — **Staging Complete; Prod Push Pending User Approval**.
- **Staging Deployment (2026-09-05)**:
  - Preview-branch path rejected (Pro plan only, $25/mo) — used a FREE second project instead: `church-staging` ref `vkognohmnqxzegxqhvmm` (eu-west-1, org vercel_icfg_JNcH8d7Gif8aFTDl8wQP3XcI). Created by orchestrator; DB password shown once at creation (user holds it).
  - All 83 migrations applied cleanly + seed (agy note: seed needed `extensions` schema in search_path for `gen_salt` — relevant if prod seed ever runs via psql outside supabase CLI).
  - Edge functions deployed to staging: analytics-export, diagnostic-engine, event-dispatcher, otp-sms (all ACTIVE). `CRON_SECRET` set (random UUID); WhatsApp/FCM secrets intentionally unset.
  - Smoke suite committed: `scripts/staging-smoke.mjs` (commit `1b10604`) — 7 checks (REST liveness, schema sanity incl. 0080 drops + 0081/0082 columns, piastres money=2000, RLS anon-blocking, RPC error contract, edge 401 contract, auth liveness). Independently re-run by orchestrator: 7/7 PASS.
  - **PROD (qksgphryemrdrkwaqnxp) UNTOUCHED**: verified frozen at migration 0078; 0079–0083 pending. Functions NOT yet deployed to prod.
- **Next Immediate Step**:
  1. Push migrations 0079–0083 + deploy functions to PROD (qksgphryemrdrkwaqnxp) after user approval; then run staging-smoke.mjs against prod.
  2. Real credentials: WhatsApp (Meta) token/phone ID/webhook secret, FCM service account — needed for notifications to actually send.
  3. Admin PWA hosting decision + Android release keystore before public distribution.

---

- **Round-2 Review Follow-Ups (2026-09-05)** — LOW-severity backlog from the 2026-09-04 review (plan: `docs/superpowers/plans/2026-09-05-review-followups.md`, implemented by agy/gemini-3.8-flash-high, verified and landed by orchestrator; zero DB changes):
  - *FUP-01 Dead Admin Screens*: deleted `apps/admin/lib/screens/home_screen.dart`, `features/auth/login_screen.dart`, `features/auth/otp_screen.dart` + their tests; `widget_test.dart` rewritten to smoke-test the real `AdminLoginScreen` (phone field + Arabic title) via `supabaseClientProvider.overrideWithValue`.
  - *FUP-02 Auth Widget Dedup*: `AuthBackgroundDecorations`/`AuthFooterLinks` extracted to `apps/mobile/lib/core/auth/widgets/auth_shared_widgets.dart`, shared by login + OTP screens (Positioned.fill variant serves both Stack call sites).
  - *FUP-03 Dead Diagnostic Files*: deleted `deno_engine.ts` (unreferenced Deno duplicate) and `test_real_{payment_flow,reconcile_payments,all_features}.ts` (imported Paymob functions deleted by migration 0070).
  - *FUP-04 Analytics Screens*: all 3 admin analytics screens (payments/bookings/utilization) now fold `Either` without throwing in setState, render Arabic error/empty states, use Arabic labels, format piastres via `formatEgp`, and dropped their no-op Export CSV buttons; `MockSupabase.failing()` test helper added with failure-path coverage.
  - *FUP-05 Export Seam*: `ExportReportButton` takes `AnalyticsRepository?` (was `dynamic client`); `AnalyticsRepository.exportPaymentsCsv()` returns `Either<Failure, String>` with Arabic messages; raw `$e` no longer leaks into SnackBars. `AnalyticsRepository._db` is `dynamic` (duck-typed to accept `FakeSupabase` in tests — contained in one private field). Second call site in `revenue_chart_widget.dart` migrated too.
  - *FUP-06 Verification Sheet*: 202-line `StatefulBuilder` modal extracted to `CertificateVerificationSheet` StatefulWidget (owns controller + dispose) in `apps/mobile/lib/features/family_archive/certificate_verification_sheet.dart`.
  - *FUP-07 Allocation Matrix Decomposition*: `build()` 297→~60 lines via `_AllocationControlsCard` (date nav + venue/priest filters) and `_UnassignedBookingsPanel` (unassigned queue); test file unchanged and passing.
  - *Housekeeping*: `opencode.json` (contains a live API key) added to `.gitignore` — never to be committed.
  - **Test Status after landing**: Flutter Admin 87/87; Flutter Mobile 94/94; Deno edge 75/75; diagnostic engine 5/5; `deno check` clean; 0 analyzer issues both apps; grep sweeps confirm zero references to deleted files.

---

---

## Prior Milestone: Full-Codebase Review Remediation (2026-09-05) — Completed & Verified.
- **Review Remediation (2026-09-05)** — fixes for the verified findings of the 2026-09-04 Gemini full-codebase review (plan: `docs/superpowers/plans/2026-09-04-review-remediation.md`, implemented by agy/gemini-3.8-flash-high, verified and landed by orchestrator):
  - *Fail-Closed Auth Gate (CRITICAL)*: `PhoneVerifyGate.checkSession()` now returns `false` on Supabase init failure instead of `true`; `isLoggedIn` callback plumbed through `ServicesListScreen` → `SlotGridScreen` for test injection.
  - *Admin UI Error Deadlocks (CRITICAL/HIGH)*: `unwrapOrThrow`/`throw f` inside `setState` eliminated across `payments_admin_screen`, `slots_admin_screen`, `faq_admin_screen`, `announcements_admin_screen`; `FutureBuilder`s check `snapshot.hasError` and render Arabic failure messages. `payment_review_queue_screen` kept `unwrapOrThrow` (its FutureBuilder already handled errors).
  - *SUPER_ADMIN Export Parity (HIGH)*: `analytics-export` `exportAllowed()` accepts `ADMIN` and `SUPER_ADMIN`.
  - *Migration 0081*: `offline_sync_log` gains `tenant_id BIGINT NOT NULL DEFAULT public.tenant_id()`, tenant-checked RLS policy, write DML revoked from `authenticated`.
  - *Migration 0082*: `audit_log.entity_uuid uuid` added; `submit_event_booking`, `admin_confirm_booking`, `admin_reject_booking`, `admin_quick_cash_collect` populate it; `apply_payment` re-created with `SET search_path = public, pg_temp`.
  - *Event Booking Route (HIGH)*: `EventBookingScreen` wired into mobile router (`/event-booking`, `AppRoutes.eventBooking`) with a home-hub quick card `حجز مناسبة خاصة` — Spec 008 flow no longer dead code.
  - *Money Unification (Migration 0083)*: legacy slot-domain money converted to integer piastres (×100): `service_slots.price`, `bookings.paid_amount`, `payments.amount`, `payment_proofs.amount_claimed`; seed price 20→2000; 12 pgTAP suites' EGP literals ×100. Client seam: `formatEgp()`/`egpToPiastres()` in both apps' `core/money_format.dart`; payment-proof/cash-entry collect EGP and convert at the seam; `_SummaryCard` retyped `int? pricePiastres`.
  - *Dead Suite Cleanup*: deleted `0077_sunday_school_management_test.sql` (entirely Sunday-school, orphaned by 0080) and stripped Sunday-school tests from `0078_operational_pivot_test.sql` (18→12 tests) — both had been failing on main since the 0080 pivot because the full sweep hadn't been run since.
  - **Test Status after landing**: pgTAP 72/72 suites PASS (full sweep, TAP-verified); Flutter Mobile 94/94; Flutter Admin 88/88; Deno edge 75/75; 0 analyzer issues both apps; migrations 0001–0083 replay cleanly via `npx supabase db reset`.
  - *RLS audit note*: `roles_permissions` has no `tenant_id` column (global RBAC catalog, policy is `is_admin()` only) — accepted as pre-existing single-tenant reference data.

---

## Prior Milestone: Code Health Improvements (CLEAN-06 – CLEAN-16) — Completed & Verified.
- **Code Health Improvements (CLEAN-10 – CLEAN-16)**:
  - *BookingDetailScreen Build Method Decomposition (CLEAN-10)*: Refactored `apps/mobile/lib/features/booking/booking_detail_screen.dart` monolithic `build()` method (226 lines) into modular private widgets: `_CountdownBanner`, `_SummaryCard`, `_WhatsappOptInCard`, `_BottomActionSheet`. All tests pass; 0 analyzer issues.
  - *OtpScreen Build Method Decomposition (CLEAN-11)*: Refactored `apps/mobile/lib/features/auth/otp_screen.dart` monolithic `build()` method (268 lines) into clean private widgets: `_BackgroundDecorations`, `_OtpHeader`, `_OtpInputRow`, `_OtpResendRow`, `_FooterLinks`. All tests pass; 0 analyzer issues.
  - *FamilyCertificatesScreen Build Method Decomposition (CLEAN-12)*: Refactored `apps/mobile/lib/features/family_archive/family_certificates_screen.dart` monolithic `build()` method (196 lines) into clean private widgets: `_ErrorView`, `_EmptyCertificatesView`, `_CertificateCard`. 0 analyzer issues.
  - *Diagnostic & Script Console Log Cleanup (CLEAN-13 – CLEAN-16)*: Removed leftover `console.log` statements in `diagnostic_engine/deno_engine.ts:99`, `diagnostic_engine/test_real_all_features.ts:10`, `diagnostic_engine/engine.ts:101`, and `scripts/test-sql.js:14`. Verified with `deno test`, `deno run`, and `node --check`.
- **Code Health Improvements (CLEAN-06 – CLEAN-09)**:
  - *LoginScreen Build Method Decomposition*: Refactored `apps/mobile/lib/features/auth/login_screen.dart` overly long monolithic `build()` method (282 lines) into clean, composable private sub-widgets: `_BackgroundDecorations`, `_LoginHeader`, `_CountryCodePrefix`, `_PhoneInputField`, `_SubmitButton`, `_FooterLinks`. Preserved all RTL directionality, phone input formatters, validator rules, and UI aesthetics. All 4 widget tests pass; 0 analyzer issues.
  - *Diagnostic Engine Console Log Cleanup*: Removed leftover ASCII banner `console.log` statements at the entry points of `diagnostic_engine/test_real_high_concurrency.ts:10`, `diagnostic_engine/test_real_analytics_export.ts:5`, and `diagnostic_engine/test_real_event_dispatcher.ts:10`. All verification runners continue to pass cleanly with exit code 0.
- **Security Fix (SEC-OTP-PII)**: Removed plain text phone number PII interpolation from `debugPrint` calls in `apps/mobile/lib/core/auth/phone_verify_gate.dart` (lines 164, 193, 207) and `apps/admin/lib/features/auth/otp_screen.dart` (line 40) (CWE-532 mitigation).
- **Client Test Status**: Mobile: 88/88 tests PASS, Admin: 80/80 tests PASS, 0 analyzer issues across both apps.
- **Forensic Review Status**:
  - Test suites verification:
    - PostgreSQL Schema: Migrations 0001–0080 replayed cleanly. 70/70 test suites pass individually (100%).
    - Deno Edge Functions: 73/73 tests PASS (plus 5 diagnostic engine tests = 78 tests total) (`deno test --allow-env --allow-net supabase/functions/`).
    - Flutter Mobile: 88/88 tests PASS, 0 analyzer issues (`apps/mobile/`).
    - Flutter Admin: 80/80 tests PASS, 0 analyzer issues (`apps/admin/`).
- **Performance Optimizations (OPT-01 – OPT-04) Completed**:
  - **OPT-01**: `test-apps/user/app.js:195` DOM NodeList caching outside tab click event loop (164.86x measured speedup).
  - **OPT-02**: `test-apps/superadmin/app.js:313` declarative `Object.fromEntries(authData.users.map(au => [au.id, au]))` replacing imperative `for...of` mutation for `authUsersMap`.
  - **OPT-03**: `supabase/functions/event-dispatcher/index.ts:310` decoupled handler execution from DB writes in `batch.map`, aggregating all `SENT` status updates into 1 bulk `.in('id', sentIds)` call per batch (81.82% DB roundtrip reduction: 110 -> 20 calls; 6.64x speedup).
  - **OPT-04**: `test-apps/user/app.js:654` Map lookup `state.slotsById.get(slotId)` with fallback to `find()` (18.36x measured speedup).
- **Next Immediate Step**:
  1. Production deployment and staging smoke tests.
  2. Optional follow-ups from 2026-09-04 two-axis code review: shared auth widgets (`_BackgroundDecorations`/`_FooterLinks` duplicated across 3 files), 202-line `_openVerificationDialog` decomposition, `_SummaryCard` `dynamic price` typing.

---

## Recent Commits / Changes
- **Outbox Handler Throw Isolation (SEC-OUTBOX-THROW, 2026-09-04)**:
  - Wrapped per-row `handler(row, deps)` calls in `event-dispatcher` `batch.map` with try/catch converting throws to `{ ok: false, retryable: true }` outcomes — one network failure can no longer reject `Promise.all`, orphan batch status writes, and trigger duplicate WhatsApp/FCM sends via the 5-min reaper.
  - Added throw-isolation test (WHATSAPP network throw → HTTP 200, row PENDING, attempts+1) and mixed-batch split-write regression test (SENT bulk + FAILED + PENDING in one batch). Dispatcher suite 8/8.
  - Fixed latent `FakeQuery.eq` test-fake bug (fake_supabase.ts): `.update().eq()` applied the update to ALL table rows before filtering; now filters first, mirroring `.in()`. Full edge suite 75/75.
  - Plan: `docs/superpowers/plans/2026-09-04-event-dispatcher-handler-isolation.md`.
- **Code Health Improvements (CLEAN-10 – CLEAN-16)**:
  - *BookingDetailScreen Build Method Decomposition (CLEAN-10)*: Refactored `apps/mobile/lib/features/booking/booking_detail_screen.dart` monolithic `build()` method (226 lines) into modular private widgets: `_CountdownBanner`, `_SummaryCard`, `_WhatsappOptInCard`, `_BottomActionSheet`. All tests pass; 0 analyzer issues.
  - *OtpScreen Build Method Decomposition (CLEAN-11)*: Refactored `apps/mobile/lib/features/auth/otp_screen.dart` monolithic `build()` method (268 lines) into clean private widgets: `_BackgroundDecorations`, `_OtpHeader`, `_OtpInputRow`, `_OtpResendRow`, `_FooterLinks`. All tests pass; 0 analyzer issues.
  - *FamilyCertificatesScreen Build Method Decomposition (CLEAN-12)*: Refactored `apps/mobile/lib/features/family_archive/family_certificates_screen.dart` monolithic `build()` method (196 lines) into clean private widgets: `_ErrorView`, `_EmptyCertificatesView`, `_CertificateCard`. 0 analyzer issues.
  - *Diagnostic & Script Console Log Cleanup (CLEAN-13 – CLEAN-16)*: Removed leftover `console.log` statements in `diagnostic_engine/deno_engine.ts:99`, `diagnostic_engine/test_real_all_features.ts:10`, `diagnostic_engine/engine.ts:101`, and `scripts/test-sql.js:14`. Verified with `deno test`, `deno run`, and `node --check`.
- **Code Health Improvements (CLEAN-06 – CLEAN-09)**:
  - *LoginScreen Build Method Decomposition*: Refactored `apps/mobile/lib/features/auth/login_screen.dart` overly long monolithic `build()` method (282 lines) into clean, composable private sub-widgets: `_BackgroundDecorations`, `_LoginHeader`, `_CountryCodePrefix`, `_PhoneInputField`, `_SubmitButton`, `_FooterLinks`. Preserved all RTL directionality, phone input formatters, validator rules, and UI aesthetics. All 4 widget tests pass; 0 analyzer issues.
  - *Diagnostic Engine Console Log Cleanup*: Removed leftover ASCII banner `console.log` statements at the entry points of `diagnostic_engine/test_real_high_concurrency.ts:10`, `diagnostic_engine/test_real_analytics_export.ts:5`, and `diagnostic_engine/test_real_event_dispatcher.ts:10`. All verification runners continue to pass cleanly with exit code 0.
- **Security Vulnerability Fix (SEC-OTP-PII)**:
  - *OTP PII Log Redaction (SEC-OTP-PII)*: Redacted raw phone numbers from error `debugPrint` statements in `apps/mobile/lib/core/auth/phone_verify_gate.dart` and `apps/admin/lib/features/auth/otp_screen.dart`, ensuring user phone numbers are never leaked to device system logs during OTP send, verify, or resend failures.
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
