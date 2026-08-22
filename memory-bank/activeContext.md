# Active Context: Church Digital Platform

## Current Focus & Status
- **Current Milestone**: Feature 010 (Review Findings Remediation) — **100% Completed & Verified**.
- **All Verification Gates Passing**:
  - Deno Edge Functions: 100 / 100 tests PASS (`deno test --allow-env --allow-net supabase/functions/`).
  - Flutter Mobile: 23 / 23 test suites PASS, 0 analyzer issues (`flutter test`, `flutter analyze` in `apps/mobile/`).
  - Flutter Admin: 23 / 23 test suites PASS, 0 analyzer issues (`flutter test`, `flutter analyze` in `apps/admin/`).
  - SQL Schema: Migrations 0001 through 0065 applied, all tests green.
- **Repository State**: Working branch `010-fix-review-findings` clean with atomic conventional commits.
- **Next Immediate Step**: Merge `010-fix-review-findings` into `main` and proceed to Feature 008 (Event Booking with Extra Services domain implementation).

---

## Deliverables & Accomplishments (Feature 010)

### 1. User Story 1 (P1): Single Payment Seam & Ownership Guards
- **Migration 0064 & 0065**:
  - `public.transition_booking_status` enforces ownership (`is_admin() OR v_book.user_id = auth.uid() OR auth.role() = 'service_role'`) across all status transitions.
  - Added `create_pending_payment(p_booking_id, p_amount, p_gateway_ref)` and `mark_payment_failed(p_payment_id)` RPCs.
  - Added `0064_transition_owner_guard_test.sql` & `0065_webhook_payment_rpc_test.sql`.
- **Edge Function Gateway Seam (`supabase/functions/_shared/payments-gateway.ts`)**:
  - Centralized all payments table interactions behind typed gateway methods (`createPendingPayment`, `markPaymentFailed`, `recordPaidPayment`).
  - Purged all direct `.from('payments')` DML across checkout, webhook, and reconcile endpoints.

### 2. User Story 2 (P1): Zero-Leak Error Contract
- Fixed `_shared/http.ts` and `otp-sms/index.ts` to eliminate exception message echoes and provider internals.
- Extended test suites across all endpoints to assert that failure bodies only contain frozen error codes (`UNAUTHORIZED|FORBIDDEN|BAD_REQUEST|UPSTREAM_ERROR|INTERNAL`) and catalog `message_ar`.

### 3. User Story 3 (P1): Browser Tooling Credential Removal
- Stripped service-role JWTs and literal passwords from `test-apps/`.
- Re-authenticated all superadmin and admin portal flows via dynamically seeded role accounts and untracked local credentials.

### 4. User Story 4 (P2): Admin Auth Clean Seam
- Removed obsolete `is_admin_or_priest` RPC invocation from `apps/admin/lib/core/auth/admin_auth_provider.dart`.
- Enforces single round-trip check on `users.role`.

### 5. User Story 5 (P2): Engineering Documentation Alignment
- Synced `docs/superpowers/plans/conventions.md` and `AGENTS.md` to live Postgres enum types (`slot_status`, `waitlist_status`, `role`).

### 6. User Story 6 (P3): Admin Typed Repository Seams
- Created 8 domain repository classes in `apps/admin/lib/features/`:
  - `AnnouncementsRepository`, `ContentRepository`, `SlotsAdminRepository`, `ManualBookRepository`, `EmergencyOverrideRepository`, `ComplaintsAdminRepository`, `PaymentsAdminRepository`, `AnalyticsRepository`.
  - Added `apps/admin/lib/core/result.dart` (`Either<Failure, T>`).
  - Purged all `dynamic get _db` and direct `.from()` / `.rpc()` calls from UI screens.
  - Added repository contract unit tests in `apps/admin/test/features/content/content_repository_test.dart`.

### 7. User Story 7 (P3): Browser Harness Consolidation
- Deleted redundant `test_portal/` directory.
- Consolidated on `test-apps/` as the sole browser testing harness.
