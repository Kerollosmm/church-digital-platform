# System Patterns & Architecture

## System Architecture Overview

```
┌────────────────────────────────────────────────────────┐
│                   Client Layer                         │
│  ┌──────────────────────────┐ ┌──────────────────────┐ │
│  │  Flutter Mobile / Web UI │ │ Flutter Admin Web    │ │
│  │  (Parishioners)          │ │ (Clergy / Staff)     │ │
│  └────────────┬─────────────┘ └──────────┬───────────┘ │
└───────────────┼──────────────────────────┼─────────────┘
                │ HTTPS                    │ HTTPS
                ▼                          ▼
┌────────────────────────────────────────────────────────┐
│            Edge & Perimeter Gateway (Supabase)         │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Deno Edge Functions                              │  │
│  │ • paymob-checkout   • paymob-webhook             │  │
│  │ • event-dispatcher  • reconcile-payments         │  │
│  │ • diagnostic-engine • analytics-export           │  │
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
│  │ • record_booking_payment• apply_payment() (srv)  │  │
│  │ • confirm_booking()     • complete_booking()     │  │
│  │ • submit_complaint_sec()• decrypt_complaint()    │  │
│  ├──────────────────────────────────────────────────┤  │
│  │ State Machine Triggers & Exclusion Constraints   │  │
│  │ • enforce_booking_status_transition              │  │
│  │ • (resource_id, tstzrange) exclusion             │  │
│  ├──────────────────────────────────────────────────┤  │
│  │ Transactional Event Outbox (event_outbox)        │  │
│  │ • FOR UPDATE SKIP LOCKED drain (Meta WhatsApp)   │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

## Key Technical Decisions & Patterns

### 1. Hardened RPC-Only Write Seam & Money Boundaries
- Direct client `INSERT/UPDATE/DELETE` is strictly prohibited on sensitive tables (`payments`, `complaints`, `audit_log`, `roles_permissions`, `users`).
- All state-changing operations occur within atomic `SECURITY DEFINER` stored procedures.
- Payments recording occurs via `public.record_booking_payment(p_booking_id, p_amount, p_gateway_ref)` which:
  1. Validates ownership or staff privileges.
  2. Inserts payment record into `public.payments` (using `gateway_ref`).
  3. Executes `apply_payment(v_pay_id)` to transition booking to `AWAITING_CALL` and enqueue WhatsApp notification.
- Functions explicitly execute:
  ```sql
  REVOKE ALL ON FUNCTION public.<func_name>(...) FROM PUBLIC, anon;
  GRANT EXECUTE ON FUNCTION public.<func_name>(...) TO authenticated, service_role;
  ```

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

### 4. Temporal Resource Conflict Prevention
- Event reservations prevent overlapping bookings for the same hall/priest using PostgreSQL exclusion constraints (`btree_gist` extension):
  ```sql
  EXCLUDE USING gist (resource_id WITH =, time_range WITH &&)
  WHERE (status NOT IN ('CANCELLED', 'REJECTED'))
  ```

### 5. Transactional Outbox Pattern
- Database triggers and RPCs never make direct HTTP calls.
- Events are enqueued into `event_outbox` inside the same database transaction.
- The `event-dispatcher` edge function queries `event_outbox` with `FOR UPDATE SKIP LOCKED` (100 rows/run, batch 10) on a 1-minute `pg_cron` schedule or via bearer auth.
- Stuck events (`PROCESSING` > timeout) are safely reaped back to `PENDING` (or marked `FAILED` after 5 attempts) via `reap_stuck_outbox_events`.

### 6. Frozen Arabic Error Contract
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
- Evaluated directly from PostgreSQL (`public.current_user_role()`), never trusting user metadata in JWTs.
- `is_admin()` checks `role IN ('ADMIN', 'SUPER_ADMIN')`.
- `is_super_admin()` checks `role = 'SUPER_ADMIN'`.

### 8. Deep Verification & Multi-Tenant Audit Invariants
- All tests run against live PostgreSQL schema inside transaction rollbacks (`BEGIN ... ROLLBACK;`).
- Multi-tenant tables enforce `tenant_id = public.tenant_id()`.
