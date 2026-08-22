# Active Context: Church Digital Platform

## Current Focus & Status
- **Current Milestone**: Full Local Backend Health Verification & Interactive Test Portals Suite (**100% Operational & Verified**).
  - All 54 SQL test suites passing over stdin via `npm run test:sql` (`node scripts/test-sql.js`) with 0 failures (`0001` through `0063`).
  - All 84 Deno edge function unit tests passing (`deno test --allow-env --allow-net supabase/functions/`).
  - Forward migrations `0055` through `0063` applied cleanly on local database reset.
  - Interactive test portals (`c:\church\test_portal\`) deployed and serving on `http://127.0.0.1:3000`.
- **Next Immediate Step**: Proceed to Feature 008 (Event Booking with Extra Services domain implementation).

---

## Recent Accomplishments & Bug Fixes (Migration 0063 & Test Portals)

### 1. Interactive Test Portal Suite (`c:\church\test_portal\`)
- Built unified browser test suite running against local Supabase (`http://127.0.0.1:54321`):
  - `index.html`: Unified Launcher Hub & backend services health probe.
  - `user.html`: Parishioner app with slot booking, seat counter, payment modal, encrypted complaints desk, announcements, and FAQs.
  - `admin.html`: Servant/Priest admin app with 2FA Admin PIN, booking queue, direct confirmation, manual booking, emergency override, and complaint decrypter.
  - `superadmin.html`: SuperAdmin portal with RBAC management, Outbox event queues, stuck event reaper, and Edge Function test runner.
  - `server.mjs`: Zero-dependency Node.js HTTP server running on port 3000.

### 2. Resolved Backend Invariants & Migration 0063 (`0063_service_role_grants_and_payment_rpc.sql`)
1. **Financial DML Boundary & `record_booking_payment` RPC**:
   - Direct client DML on `public.payments` is strictly revoked per Migration 0053.
   - Built `public.record_booking_payment(p_booking_id bigint, p_amount numeric, p_gateway_ref text)` `SECURITY DEFINER` RPC.
   - Fixed schema column mismatch: `gateway_ref` (not `gateway`).
   - Automatically executes `apply_payment(v_pay_id)` and advances booking from `PENDING_PAYMENT` to `AWAITING_CALL`.
2. **Transition Engine State Machine (`transition_booking_status`)**:
   - Updated `transition_booking_status` to permit the `apply_payment` transition (`PENDING_PAYMENT` &rarr; `AWAITING_CALL`) for non-admin callers when executing payments.
3. **Encrypted Complaints In-DB (PGCrypto)**:
   - Wired `submit_complaint_secure(p_category, p_body)` RPC for encrypted submission.
   - Integrated `v_my_complaints` view for user history and `v_complaints` + `decrypt_complaint(p_complaint_id)` for admin decryption.
4. **Manual Booking & `book_slot` Canonical Signature**:
   - Dropped stale legacy overloads of `book_slot` (`(bigint)`, `(bigint, boolean)`) and granted execute on canonical `book_slot(bigint, boolean, uuid)` to `authenticated` and `service_role`.
   - Wired `public.manual_book(p_slot_id, p_phone, p_opt_in, p_notes)` in admin portal with auto-provisioning of user profile.

---

## Live End-to-End Verified Lifecycle
```text
Step 1: User Book Slot           -> PENDING_PAYMENT  (Success)
Step 2: User Pay Online          -> AWAITING_CALL    (Success)
Step 3: Admin Phone Confirmation -> CONFIRMED        (Success)
Step 4: Admin Completion         -> COMPLETED        (Success)
```
