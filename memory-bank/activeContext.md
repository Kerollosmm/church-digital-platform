# Active Context: Church Digital Platform

## Current Focus & Status
- **Current Branch**: `004-accessibility-foundations` (Working tree holds uncommitted Feature 004 foundations + Feature 007 backend security fixes + migrations `0051`, `0052`, `0053`).
- **Feature 007 Status**: **Verified and Green**.
  - All 45 SQL test suites passing over stdin (0 failures).
  - All 84 Deno edge function unit tests passing (0 failures).
  - `apps/mobile`: `flutter analyze` clean, 82/82 tests pass.
  - `apps/admin`: `flutter analyze` clean, 45/45 tests pass.
  - Runtime Gate 6 (`functions serve` 401 JWT check) verified live on port 53321.
- **Immediate Next Step**: Spec 008 (**Event Booking Extra Services** & Flutter Clean Architecture).

## Recent Major Changes & Remediations
1. **Video Feature Decommissioning**:
   - Dropped tables `videos`, `video_purchases`, `payments.video_id`.
   - Dropped RPCs `purchase_video`, `apply_video_payment`, `deliver_personal_video`.
   - Removed `youtube-expiry` edge function, cron job, and mobile/admin UI screens.
2. **Backend Security Hardening (Migration 0053)**:
   - Revoked `INSERT, UPDATE, DELETE` from `authenticated` on sensitive tables (`payments`, `complaints`, `audit_log`, `roles_permissions`).
   - Hardened `apply_payment` to `service_role` execution only (Paymob webhook and reconcile cron only).
   - Added `SUPER_ADMIN` to `app_role` enum; purged dead `PRIEST` role references from enum.
   - Built outbox stuck event reaper (`reap_stuck_outbox_events`) and admin resend capability (`admin_resend_outbox_event`, `v_failed_outbox_events`).
   - Derived slot availability from active booking counts; removed drifting counter column `remaining_capacity`.
3. **Concurrency Test Suite Hardening (`0053_concurrency_test.sql`)**:
   - Isolated `dblink` into `dblink_test` schema to prevent privilege escalation into `public`.
   - Added bounded polling on `dblink_get_notify` for Realtime broadcast assertions.
   - Closed fixture pollution with delete-then-insert setup and explicit rollback on dblink connections.

## Key Active Decisions & Directives
- **Owner Pivot**: Personal filmed-video payment is dead. Replaced by Event Booking Extra Services.
- **Review-First Lifecycle**: Event bookings submit extras, admin approves/rejects with reasons, only then payment moves.
- **Price Snapshots**: Every booking extra records `service_name_snapshot` and `unit_price_snapshot` in piastres.
- **Dual Payment**: Webhook marks online payments `PAID`; admin RPC `admin_record_cash_payment` marks cash payments.
- **No Delegation Blind Faith**: All subagent / relay findings must be independently verified against live DB before accepting.
- **Caveman Mode (ULTRA)**: All assistant communication remains in ultra-terse caveman mode.

## Open Considerations & Pending Items
1. **Gate 7 Staging Verification**: `supabase/e2e/book_pay_flow.mjs` requires live staging Paymob secrets and test credentials.
2. **Commit Strategy**: 004 and 007 diffs remain uncommitted pending user direction on branch management.
3. **Template Validation**: `diagnostic-engine` references `admin_security_alert` which must be harmonized with outbox template check in 008.
