# Research & Architectural Decisions: Comprehensive Platform Hardening & Bug Fixes

## 1. Role Enum Synchronization (`USER` vs `PARISHIONER`)
- **Decision**: Update all RPCs (`book_slot`, `purchase_video`, RLS policies) to check for `'USER'` and `'ADMIN'` per `0033_collapse_roles.sql`.
- **Rationale**: `0033` collapsed `user_role` enum to `('USER', 'ADMIN')`. Legacy RPCs checking for `'PARISHIONER'` throw `42501 FORBIDDEN`.
- **Alternatives Considered**: Reverting to multi-role enum. Rejected because unified role architecture simplifies JWT claims and RLS InitPlans.

## 2. Capacity Restoration on Booking Expiry & Cancellation
- **Decision**: Implement trigger on `public.bookings (status)`: when status transitions from `('CONFIRMED', 'PENDING_PAYMENT')` to `('CANCELLED', 'EXPIRED', 'REFUNDED')`, atomically increment `public.service_slots.remaining_capacity` by `quantity`.
- **Rationale**: Currently `0010_lock_expiry_cron.sql`, `0008_booking_state_machine.sql`, and `0024_transition_engine.sql` cancel bookings without restoring `remaining_capacity`, permanently starving slot inventory. Trigger guarantees restoration regardless of caller.

## 3. Paymob Webhook Payload Wrapping & HMAC Unnesting
- **Decision**: Unnest `body.obj ?? body` before extracting `txn.amount_cents` and computing HMAC.
- **Rationale**: Paymob delivers transaction webhooks as `{"type": "TRANSACTION", "obj": { ... }}`. Top-level property extraction yields `undefined`, failing HMAC.

## 4. YouTube URL Video ID Regex Extraction
- **Decision**: Replace `v.yt_url.split("/").pop()` with standard regex matching `[?&]v=([a-zA-Z0-9_-]{11})` and `youtu\.be/([a-zA-Z0-9_-]{11})`.
- **Rationale**: Fixes the critical bug where standard `https://www.youtube.com/watch?v=XXXX` parsed the ID as `"watch"`.

## 5. Event Outbox Concurrency & Atomic Worker Claim
- **Decision**: Create an atomic claim RPC `claim_event_outbox_batch(p_batch_size INT)` using `SELECT id FROM event_outbox WHERE status = 'PENDING' FOR UPDATE SKIP LOCKED` and marking `PROCESSING`.
- **Rationale**: Prevents duplicate execution across concurrent edge function cron runs.

## 6. FCM HTTP v1 String Data Coercion
- **Decision**: Ensure all values in FCM `data` map are strings via `String(val)`.
- **Rationale**: Google FCM v1 API strictly rejects non-string values with HTTP 400.

## 7. SMS OTP Webhook Secret Handling
- **Decision**: Retain standard webhook secret format without stripping `whsec_` prefix.
- **Rationale**: `standardwebhooks` requires prefix for valid base64 key decoding.

## 8. pg_net Cron URL Scheme Normalization
- **Decision**: In cron migrations (`0013`, `0016`, `0020`), use `regexp_replace(url, '^https?://', '')` or normalize `SUPABASE_URL` prefixing.
- **Rationale**: Prevents `https://https://` malformed URL crashes.

## 9. Flutter Type Safety (`num.toInt()`)
- **Decision**: In `booking.dart` and `available_slot.dart`, replace `(json['paid_amount'] ?? 0) as int` with `(json['paid_amount'] as num?)?.toInt() ?? 0`.
- **Rationale**: Postgres `numeric(10,2)` deserializes as `double` / `num` in Dart, causing runtime `TypeError`.

## 10. Flutter Admin RPC Named Parameter `params:`
- **Decision**: Update all `_db.rpc(fn, {...})` calls to `_db.rpc(fn, params: {...})`.
- **Rationale**: Aligns with `supabase_flutter` v2 signature.

## 11. Admin Realtime Broadcast Subscription
- **Decision**: Update `bookings_provider.dart` to subscribe to broadcast channel `realtime:event_inventory` instead of dropped `postgres_changes` table stream.
- **Rationale**: Eliminates DB CPU load while restoring instant UI updates.