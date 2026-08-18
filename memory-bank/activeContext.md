# Active Context: Church Digital Platform

## Current Focus & Status
- **Current Branch**: `007-backend-security-fixes` (Pushed to remote `origin/007-backend-security-fixes`).
- **Feature 007 Status**: **100% Implemented, Verified, Committed, and Pushed**.
  - All 46 SQL test suites passing over stdin via `node scripts/test-sql.js` (0 failures, TAP output verified).
  - All 84 Deno edge function unit tests passing (0 failures).
  - `apps/mobile`: `flutter analyze` clean, 82/82 tests pass.
  - `apps/admin`: `flutter analyze` clean, 45/45 tests pass.
  - Gate 6 (Auth Perimeter): live HTTP verified on port 53321.
  - Gate 7 (Staging E2E): Not run (staging credentials intentionally unavailable).
- **Next Immediate Step**: Launch Feature 008 (**Event Booking Extra Services** & Clean Architecture).

## Recent Commits in This Session
1. `1bdb81a` — `docs(spec): add specification and artifacts for 004-accessibility-foundations`
2. `2eecaba` — `docs: update AGENTS.md, GEMINI.md and memory bank with event booking pivot decisions`
3. `2e3d29a` — `feat(backend): 007 backend security fixes, video decommissioning, and TAP test runner`

## Key Accomplishments & Deliverables
1. **Security Hardening (Migrations 0051–0054)**:
   - Direct client DML revoked on `payments`, `complaints`, `audit_log`, `roles_permissions`, `users`.
   - `apply_payment` locked down to `service_role` only.
   - `reap_stuck_outbox_events` and `admin_resend_outbox_event` live with `v_failed_outbox_events` (`security_invoker=true`).
   - Forward migration `0054_admin_security_alert_template.sql` deployed to allow `admin_security_alert` WhatsApp templates.
   - Slot availability derived dynamically via `active_booking_count()`; `remaining_capacity` counter dropped.
2. **Video Decommissioning**:
   - `videos`, `video_purchases`, `payments.video_id`, `purchase_video`, `apply_video_payment`, `deliver_personal_video`, and `youtube-expiry` purged across database, functions, mobile, and admin apps.
3. **pgTAP Test Runner & Concurrency Suite**:
   - Added `scripts/test-sql.js` and `scripts/sweep-sql.sh` (configured in `npm run test:sql`).
   - Hardened `0053_concurrency_test.sql` with schema `dblink_test` outside `public`.
