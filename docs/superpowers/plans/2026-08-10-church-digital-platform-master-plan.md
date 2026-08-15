# Church Digital Platform Master Implementation Plan (2026-08-10)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete, test, and ship the full Egyptian Coptic Church Digital Platform — including Landing/About Us Info, Parishioner Mobile App, Admin Web Dashboard, Supabase Postgres Backend, and Deno Edge Functions — with 100% test coverage and zero stubs.

**Architecture:** Clean Architecture + Riverpod MVVM + GoRouter on Flutter; PostgreSQL 17 + RLS + SECURITY DEFINER RPCs + pgcrypto + Vault + pg_cron on Supabase; Deno 2 Edge Functions for external integrations (Paymob, WhatsApp, YouTube, FCM v1).

**Tech Stack:** Flutter 3.x (Mobile & Web PWA), Riverpod, GoRouter, `fl_chart`, Supabase (PostgreSQL 17), Deno 2, TypeScript, Paymob Payments, Meta WhatsApp Graph API v20.0, YouTube API, FCM v1.

---

## 1. Executive Summary & Full Feature Matrix

| Feature Area | Description & Technical Seam | Key Components & Files |
| :--- | :--- | :--- |
| **Church Landing & About Us** | Church history, mass schedules, priest directory, announcements, FAQs | `v_schedule_today`, `v_available_slots`, `services`, `priests`, `faq`, `announcements`, `HomeHubScreen`, `AboutChurchScreen` |
| **Parishioner Mobile App** | Phone OTP auth, mass booking with 20-min lock TTL, Paymob iframe checkout, digital ticket with status badge, unlisted YouTube video store, encrypted complaints submission | `apps/mobile/lib/`, `SupabaseBookingRepository`, `PaymentFlowNotifier`, `BookingTicketScreen`, `VideoPurchaseScreen` |
| **Admin Web Dashboard** | Role control (`ADMIN`/`PRIEST`/`SUPER_ADMIN`), Realtime bookings & slots monitor, manual booking & emergency override modals, complaints inbox with PGP RPC decryption, analytics charts & CSV export | `apps/admin/lib/`, `AdminAuthProvider`, `BookingsAdminScreen`, `ManualBookScreen`, `ComplaintsAdminScreen`, `AnalyticsDashboard` |
| **Supabase Database Engine** | Migrations 0001–0031: RLS policies, single-writer `transition_booking_status()` engine, pgcrypto complaint encryption, unified `event_outbox`, FCM outbox triggers, realtime publication | `supabase/migrations/0001_init_schema.sql` → `0031_realtime_publication.sql`, `supabase/tests/` |
| **Deno Edge Functions** | Paymob webhook HMAC-SHA512 verification, checkout session generator, event-dispatcher (WhatsApp, Paymob Refund, FCM v1), analytics CSV export, YouTube video expiry | `supabase/functions/paymob-checkout`, `paymob-webhook`, `event-dispatcher`, `analytics-export`, `youtube-expiry` |

---

## 2. Master 10-Task Implementation Plan

### Task 1 [COMPLETE]: FCM Cloud Messaging Handler in Event Dispatcher + Migration 0029

**Files:**
- Modify: `supabase/functions/event-dispatcher/index.ts`
- Modify: `supabase/functions/event-dispatcher/index_test.ts`
- Create: `supabase/migrations/0029_fcm_outbox_triggers.sql`
- Create: `supabase/tests/0029_fcm_triggers_test.sql`

- [x] **Step 1: Write failing Deno test for FCM v1 handler**
  Add unit test in `index_test.ts` verifying `sendFcmPush` handler exchanges OAuth2 service account JWT credentials and posts to `https://fcm.googleapis.com/v1/projects/{project}/messages:send`.
- [x] **Step 2: Run Deno test to verify failure**
  Run: `deno test --allow-env supabase/functions/event-dispatcher/index_test.ts`
  Expected: FAIL with "FCM_PUSH handler not implemented"
- [x] **Step 3: Implement FCM v1 handler and migration 0029**
  Implement `sendFcmPush` in `event-dispatcher/index.ts`. Create migration `0029_fcm_outbox_triggers.sql` enqueuing `FCM_PUSH` events on booking status transitions (`AWAITING_CALL`, `CONFIRMED`, `CANCELLED`) and adding `update_fcm_token(p_token text)` RPC.
- [x] **Step 4: Run Deno and SQL tests to verify pass**
  Run: `deno test --allow-env supabase/functions/event-dispatcher/index_test.ts`
  Expected: PASS
- [x] **Step 5: Commit**
  Run: `git add supabase/functions/event-dispatcher/ supabase/migrations/0029_fcm_outbox_triggers.sql`
  Run: `git commit -m "feat(backend): add FCM v1 push notification handler and status triggers"`

---

### Task 2 [COMPLETE]: CSV Export Sanitization & Date Range Filtering

**Files:**
- Modify: `supabase/functions/analytics-export/index.ts`
- Modify: `supabase/functions/analytics-export/index_test.ts`

- [x] **Step 1: Write failing Deno test for formula injection & date filtering**
  Add test asserting string fields starting with `=`, `+`, `-`, `@`, `\t`, `\r` are escaped with a leading `'` and date parameters `from` / `to` filter rows appropriately.
- [x] **Step 2: Run Deno test to verify failure**
  Run: `deno test --allow-env supabase/functions/analytics-export/index_test.ts`
  Expected: FAIL
- [x] **Step 3: Implement formula sanitizer and date range filter**
  Add `sanitizeCsvCell` helper and handle `from`/`to` ISO query params in `analytics-export/index.ts`.
- [x] **Step 4: Run Deno test to verify pass**
  Run: `deno test --allow-env supabase/functions/analytics-export/index_test.ts`
  Expected: PASS
- [x] **Step 5: Commit**
  Run: `git add supabase/functions/analytics-export/`
  Run: `git commit -m "security(analytics): sanitize CSV cells against formula injection and add date filtering"`

---

### Task 3 [COMPLETE]: Admin Web App Authentication & Role Access Control

**Files:**
- Create: `apps/admin/lib/core/auth/admin_auth_provider.dart`
- Create: `apps/admin/lib/features/auth/admin_login_screen.dart`
- Create: `apps/admin/test/features/auth/admin_auth_test.dart`

- [x] **Step 1: Write failing widget test for Admin Role Guard**
  Test verifying users with role `PARISHIONER` are denied access and signed out, while `ADMIN`, `PRIEST`, and `SUPER_ADMIN` are granted entry.
- [x] **Step 2: Run Flutter test to verify failure**
  Run: `flutter test apps/admin/test/features/auth/admin_auth_test.dart`
  Expected: FAIL
- [x] **Step 3: Implement AdminAuthProvider & Login Screen**
  Create Riverpod `AdminAuthProvider` checking `public.users.role` against `is_admin_or_priest()`.
- [x] **Step 4: Run Flutter test to verify pass**
  Run: `flutter test apps/admin/test/features/auth/admin_auth_test.dart`
  Expected: PASS
- [x] **Step 5: Commit**
  Run: `git add apps/admin/lib/ apps/admin/test/`
  Run: `git commit -m "feat(admin): implement admin role authentication and access control provider"`

---

### Task 4 [COMPLETE]: Admin Shell Navigation & Route Registration

**Files:**
- Modify: `apps/admin/lib/app_router.dart`
- Modify: `apps/admin/test/widget/router_test.dart`

- [x] **Step 1: Write failing widget test for ShellRoute navigation**
  Assert top bar and drawer navigation items exist for (الحجوزات، حجز يدوي، طوارئ، الشكاوى، التحليلات، الفيديوهات) and navigate to corresponding screens.
- [x] **Step 2: Run Flutter test to verify failure**
  Run: `flutter test apps/admin/test/widget/router_test.dart`
  Expected: FAIL
- [x] **Step 3: Implement ShellRoute with Navigation Rail/Drawer**
  Configure `GoRouter` `ShellRoute` with Arabic navigation items in `app_router.dart`.
- [x] **Step 4: Run Flutter test to verify pass**
  Run: `flutter test apps/admin/test/widget/router_test.dart`
  Expected: PASS
- [x] **Step 5: Commit**
  Run: `git add apps/admin/lib/app_router.dart apps/admin/test/widget/router_test.dart`
  Run: `git commit -m "feat(admin): add GoRouter ShellRoute navigation for admin features"`

---

### Task 5 [COMPLETE]: Realtime Bookings & Slots Monitor + Migration 0031

**Files:**
- Create: `supabase/migrations/0031_realtime_publication.sql`
- Modify: `apps/admin/lib/features/bookings/bookings_admin_screen.dart`
- Create: `apps/admin/lib/features/bookings/bookings_provider.dart`
- Modify: `apps/admin/test/features/bookings/bookings_admin_screen_test.dart`

- [x] **Step 1: Write failing tests for Realtime channel updates**
  SQL: Verify `bookings` and `service_slots` are members of `supabase_realtime` publication. Flutter: Test provider invalidates and updates UI when `postgres_changes` payload is received.
- [x] **Step 2: Run tests to verify failure**
  Run: `flutter test apps/admin/test/features/bookings/bookings_admin_screen_test.dart`
  Expected: FAIL
- [x] **Step 3: Implement migration 0031 & Realtime provider**
  Add `0031_realtime_publication.sql` (`ALTER PUBLICATION supabase_realtime ADD TABLE public.bookings, public.service_slots;`). Subscribe to `postgres_changes` in `bookings_provider.dart`.
- [x] **Step 4: Run tests to verify pass**
  Run: `flutter test apps/admin/test/features/bookings/bookings_admin_screen_test.dart`
  Expected: PASS
- [x] **Step 5: Commit**
  Run: `git add supabase/migrations/0031_realtime_publication.sql apps/admin/`
  Run: `git commit -m "feat(admin): enable realtime updates for bookings and service slots"`

---

### Task 6 [COMPLETE]: Manual Booking & Emergency Override Screens

**Files:**
- Create: `apps/admin/lib/features/bookings/manual_book_screen.dart`
- Create: `apps/admin/lib/features/bookings/emergency_override_screen.dart`
- Create: `apps/admin/test/features/bookings/manual_book_screen_test.dart`
- Create: `apps/admin/test/features/bookings/emergency_override_screen_test.dart`

- [x] **Step 1: Write failing widget tests for RPC dialog forms**
  Test manual booking form calling `manual_book(p_slot_id, p_phone, p_opt_in, p_notes)` and emergency override form calling `emergency_override(p_booking_id, p_new_slot_id, p_refund)`.
- [x] **Step 2: Run Flutter tests to verify failure**
  Run: `flutter test apps/admin/test/features/bookings/`
  Expected: FAIL
- [x] **Step 3: Implement ManualBookScreen & EmergencyOverrideScreen**
  Create UI screens consuming `v_available_slots` and executing target SECURITY DEFINER RPCs.
- [x] **Step 4: Run Flutter tests to verify pass**
  Run: `flutter test apps/admin/test/features/bookings/`
  Expected: PASS
- [x] **Step 5: Commit**
  Run: `git add apps/admin/lib/features/bookings/ apps/admin/test/features/bookings/`
  Run: `git commit -m "feat(admin): add manual booking and emergency override admin screens"`

---

### Task 7 [COMPLETE]: Complaints Management Screen with PGP RPC Decryption

**Files:**
- Create: `apps/admin/lib/features/complaints/complaints_admin_screen.dart`
- Create: `apps/admin/test/features/complaints/complaints_admin_screen_test.dart`

- [x] **Step 1: Write failing widget test for PGP Decryption UI**
  Test rendering complaint list from `v_complaints` (no body column in view) and tapping "فك التشفير" executing `decrypt_complaint(id)` RPC to display plaintext.
- [x] **Step 2: Run Flutter test to verify failure**
  Run: `flutter test apps/admin/test/features/complaints/complaints_admin_screen_test.dart`
  Expected: FAIL
- [x] **Step 3: Implement ComplaintsAdminScreen**
  Create complaints inbox with status chips (`NEW`, `ASSIGNED`, `RESOLVED`) and on-demand RPC decryption panel.
- [x] **Step 4: Run Flutter test to verify pass**
  Run: `flutter test apps/admin/test/features/complaints/complaints_admin_screen_test.dart`
  Expected: PASS
- [x] **Step 5: Commit**
  Run: `git add apps/admin/lib/features/complaints/ apps/admin/test/features/complaints/`
  Run: `git commit -m "feat(admin): add complaints management inbox with on-demand PGP decryption"`

---

### Task 8 [COMPLETE]: Attendance & Capacity Analytics Visualization Widgets

**Files:**
- Create: `apps/admin/lib/features/analytics/attendance_chart_widget.dart`
- Create: `apps/admin/test/features/analytics/attendance_chart_test.dart`

- [x] **Step 1: Write failing widget test for fl_chart attendance bar chart**
  Test fetching data from `v_analytics_attendance` and rendering capacity vs actual attendees per service.
- [x] **Step 2: Run Flutter test to verify failure**
  Run: `flutter test apps/admin/test/features/analytics/attendance_chart_test.dart`
  Expected: FAIL
- [x] **Step 3: Implement AttendanceChartWidget with fl_chart**
  Build `fl_chart` BarChart visualization with custom tooltips and legend.
- [x] **Step 4: Run Flutter test to verify pass**
  Run: `flutter test apps/admin/test/features/analytics/attendance_chart_test.dart`
  Expected: PASS
- [x] **Step 5: Commit**
  Run: `git add apps/admin/lib/features/analytics/ apps/admin/test/features/analytics/`
  Run: `git commit -m "feat(admin): add attendance and capacity utilization bar chart widget"`

---

### Task 9 [COMPLETE]: Revenue & Payment Breakdown Dashboard

**Files:**
- Create: `apps/admin/lib/features/analytics/revenue_chart_widget.dart`
- Create: `apps/admin/lib/features/analytics/export_report_button.dart`
- Create: `apps/admin/test/features/analytics/revenue_chart_test.dart`

- [x] **Step 1: Write failing widget test for revenue pie chart & CSV export**
  Test fetching `v_analytics_revenue` for pie chart rendering and clicking "تصدير التقرير" triggering `analytics-export` Edge Function.
- [x] **Step 2: Run Flutter test to verify failure**
  Run: `flutter test apps/admin/test/features/analytics/revenue_chart_test.dart`
  Expected: FAIL
- [x] **Step 3: Implement RevenueChartWidget & ExportReportButton**
  Build `fl_chart` PieChart and wire Edge Function CSV stream downloader.
- [x] **Step 4: Run Flutter test to verify pass**
  Run: `flutter test apps/admin/test/features/analytics/revenue_chart_test.dart`
  Expected: PASS
- [x] **Step 5: Commit**
  Run: `git add apps/admin/lib/features/analytics/ apps/admin/test/features/analytics/`
  Run: `git commit -m "feat(admin): add revenue breakdown pie chart and CSV export downloader"`

---

### Task 10 [COMPLETE]: Full System DoD Verification & Source-of-Truth Sync

**Files:**
- Modify: `docs/superpowers/plans/conventions.md`
- Modify: `docs/superpowers/plans/2026-08-05-church-digital-platform.md`

- [x] **Step 1: Update source-of-truth documentation**
  Update `conventions.md` and master plan §5/§6 to record FCM v1 integration, `0029-0031` migrations, and `event_outbox` status.
- [x] **Step 2: Execute all test suites**
  Run Deno tests: `deno test --allow-env supabase/functions/`
  Run Mobile tests: `flutter test apps/mobile/test`
  Run Admin tests: `flutter test apps/admin/test`
  Expected: ALL PASS with 0 failures.
- [x] **Step 3: Commit**
  Run: `git add docs/superpowers/plans/`
  Run: `git commit -m "docs(project): sync master platform conventions and complete definition of done"`

---

## 3. Non-Negotiable Technical Rules & Guardrails
1. **State Modifications ONLY via RPCs**: Money, bookings, overrides, and complaints MUST go through `SECURITY DEFINER` RPCs with `SET search_path = public`. Apps never issue direct `INSERT`/`UPDATE` on core tables.
2. **RLS Mandatory**: Every new table requires `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;` before policies.
3. **TypeScript Strictness**: Defensive error catching, CORS handling, and formula injection sanitization on CSV exports.
4. **Clean Code & Terse Style**: No placeholders, no `TBD`, no swallowed exceptions.
