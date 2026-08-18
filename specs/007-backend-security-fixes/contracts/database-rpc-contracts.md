# Database RPC Contracts: 007-backend-security-fixes

All signatures verified against the live `supabase_db_church` database on 2026-08-17. A `REVOKE`
naming a signature that does not exist aborts the whole migration, so these must be exact.

---

## 1. `apply_payment`

Transitions a payment to `PAID`, moves the associated booking to `AWAITING_CALL`, and enqueues the
WhatsApp confirmation outbox event.

- **Signature**: `public.apply_payment(p_payment_id bigint)` — **one argument**. The
  three-argument `(bigint, text, jsonb)` form does not exist. Gateway metadata is written by the
  caller (`paymob-webhook`) before invoking this RPC, into `payments.gateway_ref`,
  `payments.merchant_order_id`, and `payments.raw_webhook`. There are no `gateway_order_id` or
  `raw_payload` columns.
- **Security**: `SECURITY DEFINER`. Body is **not** changed by 007 — privileges only.
- **Current state**: `proacl IS NULL`, i.e. PostgreSQL's default `EXECUTE TO PUBLIC`, with no caller
  check of any kind. Combined with a sequential `bigint` primary key, anyone holding the anon key can
  confirm an arbitrary payment.
- **Privilege change**:
  ```sql
  REVOKE ALL ON FUNCTION public.apply_payment(bigint) FROM PUBLIC, anon, authenticated;
  GRANT EXECUTE ON FUNCTION public.apply_payment(bigint) TO service_role;
  ```
- **Callers** (both already service-role): `supabase/functions/paymob-webhook/index.ts:148`,
  `supabase/functions/reconcile-payments/index.ts:105`.
- **Postconditions**: `payments.status = 'PAID'`; if the linked booking is `PENDING_PAYMENT` it
  transitions to `AWAITING_CALL`; exactly one `booking_confirmed` row is inserted into
  `event_outbox`. Idempotent no-op when the payment is already `PAID`.

---

## 2. `book_slot` (consolidated)

- **Signature**:
  `public.book_slot(p_slot_id bigint, p_opt_in boolean DEFAULT false, p_idempotency_key uuid DEFAULT NULL) RETURNS public.bookings`
- **Replaces**: `book_slot(bigint, boolean)` from 0048 and `book_slot(bigint, integer, boolean, uuid)`
  from 0039. Both are dropped, along with the helper `fn_book_slot_atomic`.
- **`p_opt_in` is the WhatsApp opt-in flag.** It must keep that name: mobile calls the RPC with named
  arguments (`supabase_booking_repository.dart:55`) and a test asserts the exact argument map
  (`booking_flow_test.dart:55`).
- **Dropped capability**: `p_quantity`. `bookings.seat_count` is fixed at 1. No client passes a
  quantity; multi-seat pricing is feature 008's concern.
- **Security**: `SECURITY DEFINER`.
  ```sql
  REVOKE ALL ON FUNCTION public.book_slot(bigint, boolean, uuid) FROM PUBLIC, anon;
  GRANT EXECUTE ON FUNCTION public.book_slot(bigint, boolean, uuid) TO authenticated;
  ```
  The old 4-arg overload was PUBLIC-executable; that surface disappears with it.
- **Preconditions**: slot exists and `deleted_at IS NULL`; `slot.starts_at > now()`;
  `active_booking_count(p_slot_id) < slot.capacity`.
- **Locking**: `SELECT capacity FROM public.service_slots WHERE id = p_slot_id FOR UPDATE` before the
  capacity test, so concurrent callers serialise on the slot row.
- **Side effect**: emits the `SLOT_EXHAUSTED` `pg_notify` payload formerly produced by
  `fn_broadcast_slot_depletion` when the post-insert active count reaches `capacity`.
- **Errors**: `SLOT_NOT_FOUND`, `SLOT_FULL`, `SLOT_CLOSED`, `AUTH_REQUIRED` (mapped by the mobile
  repository from SQLSTATE `28000`).

---

## 3. `expire_stale_bookings`

- **Signature**: `public.expire_stale_bookings() RETURNS integer`
- **Current state**: `proacl IS NULL` → PUBLIC-executable. Invoked by pg_cron jobid 1 every minute as
  `select public.expire_stale_bookings();`, which runs as `postgres`.
- **Privilege change**:
  ```sql
  REVOKE ALL ON FUNCTION public.expire_stale_bookings() FROM PUBLIC, anon, authenticated;
  GRANT EXECUTE ON FUNCTION public.expire_stale_bookings() TO service_role, postgres;
  ```
- **Behaviour change**: the candidate select gains row locking. The deadline column is
  **`bookings.locked_until`** — there is no `bookings.expires_at`:
  ```sql
  SELECT id, slot_id FROM public.bookings
   WHERE status = 'PENDING_PAYMENT' AND locked_until < now()
     FOR UPDATE SKIP LOCKED;
  ```
- **Target status is `CANCELLED`, not `EXPIRED`.** `booking_status` has no `EXPIRED` label and
  `bookings_status_check` would reject it. The existing body already delegates to
  `transition_booking_status(r.id, 'CANCELLED', 'expire_lock', 'stale payment lock', ...)` and then
  `promote_waiting_list(r.slot_id)`; 007 preserves both calls.
- **Returns**: number of bookings cancelled.

---

## 4. `promote_waiting_list` / `materialize_analytics` / `rbac_allows`

Privilege-only changes; bodies untouched.

```sql
REVOKE ALL ON FUNCTION public.promote_waiting_list(bigint)  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.promote_waiting_list(bigint)  TO service_role, postgres;

REVOKE ALL ON FUNCTION public.materialize_analytics()       FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.materialize_analytics()       TO service_role, postgres;

-- unguarded, PUBLIC-executable, and no caller exists in any function or policy
REVOKE ALL ON FUNCTION public.rbac_allows(public.app_role, text, text) FROM PUBLIC, anon;
```

`active_booking_count(bigint, boolean)` is deliberately **left alone**: it is read-only, already
granted only to `authenticated` and `service_role` beyond PUBLIC, and `v_available_slots` depends on
it. `decrypt_complaint`, `emergency_override`, `cancel_booking`, `confirm_booking`,
`complete_booking`, `join_waiting_list`, and `manual_book` are PUBLIC-executable but carry internal
`current_user_role()` / `is_admin()` / `auth.uid()` guards and are also out of scope.

---

## 5. `reap_stuck_outbox_events`

- **Signature**: `public.reap_stuck_outbox_events(p_timeout interval DEFAULT interval '5 minutes') RETURNS integer`
- **Security**: `SECURITY DEFINER`.
  ```sql
  REVOKE ALL ON FUNCTION public.reap_stuck_outbox_events(interval) FROM PUBLIC, anon, authenticated;
  GRANT EXECUTE ON FUNCTION public.reap_stuck_outbox_events(interval) TO service_role, postgres;
  ```
- **Schema prerequisite**: `event_outbox` has no `updated_at` and no `locked_until`, so the timeout
  cannot be evaluated on the current table. 007 adds `claimed_at timestamptz` (written by
  `claim_event_outbox_batch`) and `last_error text`.
- **Selection**: `status = 'PROCESSING' AND claimed_at < now() - p_timeout`, claimed with
  `FOR UPDATE SKIP LOCKED`.
- **Transition** — the `attempts >= 5` branch is required by `event_outbox_attempts_check`
  (`attempts >= 0 AND attempts <= 5`); an unconditional increment would abort the reaper:
  - `attempts >= 5` → `status = 'FAILED'`, `last_error = 'reaped: stuck in PROCESSING at max attempts'`
  - otherwise → `status = 'PENDING'`, `attempts = attempts + 1`, `next_attempt_at = now()`,
    `claimed_at = NULL`
- **Schedule**: pg_cron every 5 minutes.
- **Returns**: number of rows touched.

---

## 6. `admin_resend_outbox_event`

- **Signature**: `public.admin_resend_outbox_event(p_event_id bigint) RETURNS jsonb`
- **Security**: `SECURITY DEFINER`, internal `is_admin()` guard.
  ```sql
  REVOKE ALL ON FUNCTION public.admin_resend_outbox_event(bigint) FROM PUBLIC, anon;
  GRANT EXECUTE ON FUNCTION public.admin_resend_outbox_event(bigint) TO authenticated;
  ```
- **Postconditions**: `status = 'PENDING'`, `attempts = 0`, `last_error = NULL`,
  `next_attempt_at = now()`, `claimed_at = NULL`.
- **Returns**: `{"success": true, "event_id": 123, "status": "PENDING"}`
- **Errors**: `FORBIDDEN` (non-admin caller), `EVENT_NOT_FOUND`.

---

## 7. `v_failed_outbox_events`

Read surface backing the staff backlog. Exposes `id`, `handler_type`, `status`, `attempts`,
`next_attempt_at`, `claimed_at`, `last_error`, `created_at`, and the recipient/template fields
extracted from `payload`. Created `WITH (security_invoker = true)` and readable only through an
`is_admin()` predicate, so it cannot become an RLS bypass in the way `v_complaints`
(`security_invoker=false`) already is.

The Flutter backlog screen itself is **out of 007 scope** and lands in feature 008 with the
clean-architecture rework; 007 delivers the view and the RPC only.
