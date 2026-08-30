# System Patterns & Architecture

## System Architecture Overview

```
┌────────────────────────────────────────────────────────┐
│                   Client Layer                         │
│  ┌──────────────────────────┐ ┌──────────────────────┐ │
│  │  Flutter Mobile UI       │ │ Flutter Admin Web    │ │
│  │  (Parishioners)          │ │ (Clergy / Staff)     │ │
│  │  [Typed Repositories]    │ │ [Typed Repositories] │ │
│  └────────────┬─────────────┘ └──────────┬───────────┘ │
└───────────────┼──────────────────────────┼─────────────┘
                │ HTTPS                    │ HTTPS
                ▼                          ▼
┌────────────────────────────────────────────────────────┐
│            Edge & Perimeter Gateway (Supabase)         │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Deno Edge Functions                              │  │
│  │ • event-dispatcher  • otp-sms                    │  │
│  │ • diagnostic-engine • analytics-export           │  │
│  │ • offline-sync                                   │  │
│  │ • _shared/payments-gateway.ts (Unified Seam)     │  │
│  │ • _shared/http.ts (Zero-Leak Error Contract)     │  │
│  └──────────────────────────┬───────────────────────┘  │
└─────────────────────────────┼──────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────┐
│             Database Core (PostgreSQL 16)              │
│  ┌──────────────────────────────────────────────────┐  │
│  │ RLS Policies + Tenant Isolation (tenant_id)      │  │
│  ├──────────────────────────────────────────────────┤  │
│  │ SECURITY DEFINER RPC Write Seam                  │  │
│  │ • book_slot()           • manual_book()          │  │
│  │ • submit_payment_proof  • approve_payment_proof  │  │
│  │ • reject_payment_proof  • mark_cash_received     │  │
│  │ • submit_event_booking  • admin_confirm_booking  │  │
│  │ • admin_reject_booking  • admin_quick_cash_collect│ │
│  │ • submit_complaint_sec()• decrypt_complaint()    │  │
│  ├──────────────────────────────────────────────────┤  │
│  │ State Machine Triggers & Exclusion Constraints   │  │
│  │ • transition_booking_status (Owner Guarded)      │  │
│  │ • (assigned_venue_id, tstzrange) GiST exclusion  │  │
│  ├──────────────────────────────────────────────────┤  │
│  │ Transactional Event Outbox (event_outbox)        │  │
│  │ • FOR UPDATE SKIP LOCKED drain (Meta WhatsApp)   │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

## Key Technical Decisions & Patterns

### 1. Hardened RPC-Only Write Seam & Manual Payment Verification Rail (Feature 011 / ADR 0003)
- Direct client `INSERT/UPDATE/DELETE` is strictly prohibited on sensitive tables (`payments`, `payment_proofs`, `event_bookings`, `complaints`, `audit_log`, `roles_permissions`, `users`).
- All state-changing operations occur within atomic `SECURITY DEFINER` stored procedures.
- Payments lifecycle is managed via:
  - `submit_payment_proof(p_booking_id, p_channel, p_sender_phone, p_reference_number, p_amount_claimed, p_image_path)`: Submits member receipt.
  - `approve_payment_proof(p_proof_id, p_collector_note)`: Validates proof with `FOR UPDATE` lock, invokes `apply_payment`.
  - `reject_payment_proof(p_proof_id, p_reason_code)`: Rejects proof with catalog reason code.
  - `mark_cash_received(p_booking_id, p_amount, p_collector_note)`: Records in-person cash payment on slot bookings.
  - `admin_quick_cash_collect(p_booking_id, p_amount_piastres, p_collector_note)`: One-click cashier collection on event bookings.
  - `apply_payment(p_payment_id)`: `service_role`-only RPC executing state transition and enqueuing outbox messages.
- Edge functions and clients interact with financial data exclusively via `_shared/payments-gateway.ts`.

### 2. High-Concurrency Slot Reservation
- Slot capacity is locked via `SELECT capacity FROM service_slots WHERE id = p_slot_id FOR UPDATE`.
- Dynamic availability is calculated by counting active non-cancelled/non-expired bookings against slot capacity.
- Canonical signature: `public.book_slot(p_slot_id bigint, p_opt_in boolean DEFAULT false, p_idempotency_key uuid DEFAULT null)`.
- Eliminates drifting counter columns and double-booking races under concurrent load.

### 3. In-DB PGCrypto Complaints System
- Direct table access on `complaints` is blocked (`SELECT false`).
- Users submit via `submit_complaint_secure(p_category, p_body)` which encrypts details with `COMPLAINTS_KEY` from Supabase Vault.
- Users read non-sensitive fields from `v_my_complaints` view.
- Admins read from `v_complaints` view and invoke `decrypt_complaint(p_complaint_id)` RPC to decrypt on demand.

### 4. Client Data Layer Architecture (Feature 010 / US6)
- **Typed Repository Seams**: Admin and mobile apps forbid direct database access (`Supabase.instance.client`, `dynamic get _db`) inside screens.
- Every feature screen receives a typed repository via constructor injection:
  - Return types wrapped in `Either<Failure, T>` to prevent raw exception leaks.
  - Mocking accomplished via `MockSupabase` HTTP transport simulation for real client unit testing.

### 5. Transactional Outbox Pattern
- Database triggers and RPCs never make direct HTTP calls.
- Events are enqueued into `event_outbox` inside the same database transaction.
- The `event-dispatcher` edge function queries `event_outbox` with `FOR UPDATE SKIP LOCKED` (100 rows/run, batch 10) on a 1-minute `pg_cron` schedule or via bearer auth.
- Stuck events (`PROCESSING` > timeout) are safely reaped back to `PENDING` (or marked `FAILED` after 5 attempts) via `reap_stuck_outbox_events`.

### 6. Frozen Arabic Error Contract (Feature 010 / US2)
- All client-facing failures adhere to the frozen contract:
  ```json
  {
    "error": "UNAUTHORIZED",
    "message_ar": "انتهت الجلسة، من فضلك سجل الدخول مرة أخرى."
  }
  ```
- Allowed error codes are strictly limited to:
  `UNAUTHORIZED` | `FORBIDDEN` | `BAD_REQUEST` | `UPSTREAM_ERROR` | `INTERNAL`
- Edge functions return 500 errors with zero runtime stack leak in payload.

### 7. Role-Based Access Control (RBAC)
- Role hierarchy: `USER` -> `ADMIN` -> `SUPER_ADMIN`.
- PRIEST role tier purged across database enums, edge functions, and client code.
- Admin UI routes strictly verify `role IN ('ADMIN', 'SUPER_ADMIN')` directly from Postgres without metadata fallbacks.
