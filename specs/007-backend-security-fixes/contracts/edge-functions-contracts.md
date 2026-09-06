# Edge Function Contracts: 007-backend-security-fixes

Behaviour marked **[TO BUILD]** does not exist yet and is a deliverable of this feature. Behaviour
marked **[CURRENT]** was verified in the working tree on 2026-08-17.

---

## 1. `reconcile-payments`

Cron-driven sweep that reconciles pending transactions against Paymob. Invoked by pg_cron jobid 2
(`30 3 * * *`) via `net.http_post` with `Authorization: Bearer <SERVICE_ROLE_KEY>` read from Vault.

- **Trigger**: HTTP POST / scheduled cron.
- **Inbound authentication** — **[TO BUILD]**. The function currently performs **no** inbound
  authorization check; the only `Authorization` headers in the file are outbound. Any unauthenticated
  caller can trigger a reconciliation sweep. 007 adds a constant-time comparison of the inbound
  bearer token against `CRON_SECRET` or `SUPABASE_SERVICE_ROLE_KEY`, returning `401 UNAUTHORIZED`
  with the frozen Arabic error body on mismatch. The pg_cron job already sends the service-role key,
  so no cron change is required.
- **Behaviour contract**:
  - Selects `public.payments` where `status = 'CREATED'` beyond the reconciliation window.
  - Queries the Paymob order/transaction status for each.
  - **Paid** → invokes `public.apply_payment(p_payment_id)` (single argument).
  - **Terminal decline / cancellation / expiry** → invokes `mark_payment_failed`.
  - **Transient upstream failure** — **[TO BUILD]**. `index.ts:48-57` currently calls
    `markPaymentFailed` on *any* non-2xx, including 502/503/504 and timeouts. Because the sweep only
    selects `status = 'CREATED'`, such a payment is never re-examined: a parishioner who genuinely
    paid is left permanently `FAILED` with no booking. Required behaviour is to log the payment id
    and HTTP status via `console.error`, **not** call `mark_payment_failed`, and `continue` to the
    next payment so the next scheduled sweep re-evaluates it.
- **Response format**:
  - `200 OK`: `{"status": "ok", "reconciled": 5, "skipped": 1, "failed": 0}`
  - `401 Unauthorized`: missing or invalid bearer token.
  - `500`: non-leaking `{"error": "INTERNAL", "message_ar": "..."}`.

---

## 2. `paymob-checkout`

Creates a localized payment intention and returns an iframe URL.

- **Trigger**: HTTP POST `/paymob-checkout`.
- **Authentication**: Bearer JWT (parishioner). **[CURRENT]** — already enforced.
- **Secret validation** — **[TO BUILD]**. `PAYMOB_INTEGRATION_ID` and `PAYMOB_IFRAME_ID` currently
  default to the string `"0"`, which silently produces invalid checkout URLs. 007 validates
  `PAYMOB_API_KEY`, `PAYMOB_INTEGRATION_ID`, `PAYMOB_IFRAME_ID`, and `PAYMOB_HMAC_SECRET` at module
  scope and throws if any is absent, empty, or `"0"`.
  - **Interaction with quickstart Gate 6**: module-scope validation means the function will not boot
    when those variables are unset, so the Arabic 401 sweep against this endpoint would fail for the
    wrong reason. Quickstart therefore requires non-`"0"` placeholder values in
    `supabase/functions/.env` for local runs. Do **not** weaken the check to keep the gate green, and
    do **not** introduce a new error code — the error-code contract is frozen.
- **Request body**: `{"booking_id": 123}`
- **Response format**:
  - `200 OK`: `{"payment_id": 456, "checkout_url": "...", "amount": 25000, "currency": "EGP"}`
    (`amount` is integer piastres).
  - `400`: invalid or already-paid booking.
  - `502`: `{"error": "UPSTREAM_ERROR", "message_ar": "..."}`.

---

## 3. `event-dispatcher`

Drains `public.event_outbox` and dispatches WhatsApp messages via the Meta Cloud API. Invoked by
pg_cron jobid 3 every minute with the service-role bearer token.

- **Inbound authentication** — **[TO BUILD]**, same gap and same fix as `reconcile-payments`.
- **Claim** — **[CURRENT]**: `claim_event_outbox_batch(p_batch_size)` with
  `FOR UPDATE SKIP LOCKED`, already restricted to `service_role` by 0041.
- **New writes** — **[TO BUILD]**: set `event_outbox.claimed_at` on claim (inside
  `claim_event_outbox_batch`) and `event_outbox.last_error` on a failed dispatch, so
  `reap_stuck_outbox_events` has a timeout basis and `v_failed_outbox_events` has failure context.
- **Template allow-list** — the verified value of `event_outbox_whatsapp_template_check` is
  `booking_confirmed, payment_received, booking_cancelled, booking_rescheduled, booking_apology,
  otp_auth, booking_payment_received, booking_offer, video_ready`. 007 removes only `video_ready`,
  from both the constraint and the dispatcher's handler map. There is no `payment_receipt` template —
  do not add one.
- **Response format**: `200 OK`: `{"status": "ok", "processed": 10, "failed": 0}`.

---

## 4. Deleted functions

| Path | Reason |
|---|---|
| `supabase/functions/youtube-expiry/` | Product pivot. Its pg_cron job (jobid 4, `0 4 * * *`) is live and must be unscheduled in the migration, otherwise the cron keeps POSTing to a dead endpoint every day |
| `supabase/functions/deliver-personal-video/` | Product pivot. Untracked in git — added by feature 004 and removed before it ever shipped |
