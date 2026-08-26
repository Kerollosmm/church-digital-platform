# Active Context: Church Digital Platform

## Current Focus & Status
- **Current Milestone**: Feature 008 (Event Booking with Extra Services — ADR 0002) — **100% Completed & Verified**.
- **All Verification Gates Passing**:
  - PostgreSQL Schema: Migrations 0001 through 0074 applied; 64 / 64 SQL suites PASS (`node scripts/test-sql.js`).
  - Deno Edge Functions: 58 / 58 test suites PASS (`deno test --allow-env --allow-net supabase/functions/`).
  - Flutter Mobile: 81 / 81 tests PASS, 0 analyzer issues (`flutter test`, `flutter analyze` in `apps/mobile/`).
  - Flutter Admin: 65 / 65 tests PASS, 0 analyzer issues (`flutter test`, `flutter analyze` in `apps/admin/`).
- **Research Tooling Integration**: Configured `notebooklm-mcp` in `~/.gemini/antigravity/mcp_config.json` and `~/.gemini/config/mcp_config.json` with authenticated access to project research notebook `Flutter with Supabase Research` (`63ddabc2-5d6c-493c-8e2d-d61271d0c4db`, 30 sources). Integrated into `/memory-bank` protocol and `techContext.md`.
- **Repository State**: Working branch `008-event-booking-extra-services` with verified end-to-end integration.
- **Next Immediate Step**: Review and integrate branch changes into main.

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
