# System Patterns & Architecture

## System Architecture Overview

```
┌────────────────────────────────────────────────────────┐
│                   Client Layer                         │
│  ┌──────────────────────────┐ ┌──────────────────────┐ │
│  │  Flutter Mobile App      │ │ Flutter Web Admin    │ │
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
│  │ • admin_confirm_booking • admin_reject_booking   │  │
│  │ • apply_payment() (srv) • admin_record_cash()    │  │
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

### 1. Hardened RPC-Only Write Seam
- Direct client `INSERT/UPDATE/DELETE` is strictly prohibited on sensitive tables (`payments`, `complaints`, `audit_log`, `roles_permissions`).
- All state-changing operations occur within atomic `SECURITY DEFINER` stored procedures.
- Functions explicitly execute:
  ```sql
  REVOKE ALL ON FUNCTION public.<func_name>(...) FROM PUBLIC, anon, authenticated;
  GRANT EXECUTE ON FUNCTION public.<func_name>(...) TO service_role; -- or authenticated
  ```
- Public/anon execution of money transitions (`apply_payment`) is strictly blocked.

### 2. High-Concurrency Slot Reservation
- Slot capacity is locked via `SELECT capacity FROM service_slots WHERE id = p_slot_id FOR UPDATE`.
- Dynamic availability is calculated by counting active non-cancelled/non-expired bookings against slot capacity.
- Eliminates drifting counter columns and double-booking races under concurrent load.

### 3. Temporal Resource Conflict Prevention
- Event reservations prevent overlapping bookings for the same hall/priest using PostgreSQL exclusion constraints (`btree_gist` extension):
  ```sql
  EXCLUDE USING gist (resource_id WITH =, time_range WITH &&)
  WHERE (status NOT IN ('CANCELLED', 'REJECTED'))
  ```

### 4. Transactional Outbox Pattern
- Database triggers and RPCs never make direct HTTP calls.
- Events are enqueued into `event_outbox` inside the same database transaction.
- The `event-dispatcher` edge function queries `event_outbox` with `FOR UPDATE SKIP LOCKED` (100 rows/run, batch 10) on a 1-minute `pg_cron` schedule.
- Stuck events (`PROCESSING` > timeout) are safely reaped back to `PENDING` (or marked `FAILED` after 5 attempts) via `reap_stuck_outbox_events`.

### 5. Frozen Arabic Error Contract
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

### 6. Role-Based Access Control (RBAC)
- Role hierarchy: `USER` -> `ADMIN` -> `SUPER_ADMIN`.
- Evaluated directly from PostgreSQL (`public.current_user_role()`), never trusting user metadata in JWTs.
- `is_admin()` checks `role IN ('ADMIN', 'SUPER_ADMIN')`.
- `is_super_admin()` checks `role = 'SUPER_ADMIN'`.

### 7. Flutter Application Patterns
- **State Management**: Riverpod `AsyncNotifier` / `StateNotifier` for predictable, immutable state flows.
- **Routing**: `GoRouter` with top-level auth and role redirect guards.
- **Startup Fail-Fast**: `main.dart` asserts non-empty `SUPABASE_ANON_KEY` and throws `StateError` on missing environment.
- **Failures as Values**: Repositories return `Either<Failure, Success>` with zero raw unhandled exceptions leaking to UI widgets.
