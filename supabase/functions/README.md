# Supabase Edge Functions — Shared Kernel & Service Catalog

This directory contains the Deno Edge Functions for the Egyptian Coptic Church Digital Platform.

## 1. Shared Kernel (`_shared/`)

All edge functions share a centralized core kernel:
- **`_shared/http.ts`**: Identity verification and response serialization seam.
  - `auth(req, { requireStaff?: boolean })`: Verifies caller's Bearer JWT against Supabase Auth (`getUser`). Gated endpoints reject invalid/missing tokens with standard 401 `UNAUTHORIZED` or non-staff users with 403 `FORBIDDEN`. Handles CORS OPTIONS pre-flight automatically.
  - `respond(status, codeOrBody, message?, extra?)`: Unified response and error emitter. Injects standard CORS headers (`Access-Control-Allow-Origin: *`, `Access-Control-Allow-Headers: ...`) on every response and formats errors conforming to `{"error": CODE, "message": string?}` (`UNAUTHORIZED`, `FORBIDDEN`, `BAD_REQUEST`, `UPSTREAM_ERROR`, `INTERNAL`).
- **`_shared/paymob.ts`**: Standardized payment gateway adapter.
  - `createPaymob({ apiKey, baseUrl?, fetch? })`: Reusable client implementing `session()`, `checkout()`, `refund()`, `orderStatus()`, and `hmacFields()`.
  - Auth tokens are cached in-memory until `expires_in - 60s` to eliminate redundant auth requests.
  - Formats upstream errors (non-2xx and unparseable JSON) as 502 `UPSTREAM_ERROR`.
- **`_shared/client.ts`**: Supabase service-role client factory (`makeServiceClient`).
- **`_shared/fake_supabase.ts`**: In-memory database and RPC fake for fast deterministic test suites.

## 2. Functions Catalog (9 Functions)

All 9 functions disable gateway-level JWT verification in `supabase/config.toml` (`verify_jwt = false`) to enforce application-layer authentication and deterministic error payloads.

| Function | Auth Mechanism | Purpose / Description |
| :--- | :--- | :--- |
| `paymob-checkout` | User Bearer JWT (`auth()`) | Initiates Paymob payment key & returns iframe URL |
| `paymob-webhook` | HMAC-SHA512 (`hmacFields`) | Processes Paymob transaction webhooks with idempotency guard |
| `event-dispatcher` | Internal / pg_cron | Drains `event_outbox` (WhatsApp, Paymob refunds, FCM push) |
| `reconcile-payments` | Internal / pg_cron | Polls stale `PENDING_PAYMENT` transactions against Paymob API |
| `youtube-expiry` | Internal / pg_cron | Flips expired unlisted YouTube videos to private via OAuth2 |
| `otp-sms` | StandardWebhooks | Dispatches SMS/WhatsApp OTP auth templates via Meta Graph API |
| `diagnostic-engine` | Staff Bearer JWT (`auth({ requireStaff: true })`) | Executes security invariants, RLS penetration probes, and telemetry |
| `analytics-export` | Staff Bearer JWT (`auth({ requireStaff: true })`) | Exports sanitized CSV reports (utilization, payments, bookings) |
| `offline-sync` | User Bearer JWT (`auth()`) | Batch syncs mobile offline mutations via `sync_offline_mutations` RPC |

## 3. Core Invariants & Architecture Rules

1. **Zero Raw Table Business Mutations**: All financial, booking, and slot status state transitions are executed via `SECURITY DEFINER` SQL RPCs (`book_slot`, `apply_payment`, `apply_video_payment`, `cancel_booking`, `claim_event_outbox_batch`).
2. **Atomic Outbox Leasing**: Background dispatchers (`event-dispatcher`) lease queue batches strictly via `claim_event_outbox_batch` with `FOR UPDATE SKIP LOCKED` (no non-atomic fallback query; RPC errors abort the run to prevent race conditions).
3. **In-Memory Token Caching**: External OAuth2 and gateway session tokens (Paymob `expires_in - 60s`, FCM `expires_in - 60s`) are cached in memory to prevent rate-limiting and latency overhead.
4. **Upstream Error Resilience**: Payment reconciliation (`reconcile-payments`) never cancels bookings on upstream HTTP timeouts or transient 5xx errors; it only fails after definitive confirmation.
5. **Role-Gated Diagnostics & Export**: Diagnostic and analytics export endpoints strictly require valid Bearer authentication with staff roles (`ADMIN`, `PRIEST`, `SUPER_ADMIN`).

## 4. Diagnostic Probe Example

To execute the diagnostic engine against a running environment:

```bash
# Requires an active ADMIN JWT token
curl -X POST "https://<PROJECT_REF>.supabase.co/functions/v1/diagnostic-engine" \
  -H "Authorization: Bearer <ADMIN_JWT_TOKEN>" \
  -H "Content-Type: application/json"
```

Sample Response:
```json
{
  "success": true,
  "timestamp": "2026-08-16T12:00:00.000Z",
  "probes_executed": 3,
  "critical_count": 0,
  "status": "100% SECURE & INVARIANT-COMPLIANT",
  "findings": [],
  "logs": [
    { "id": "SEC-ANON-USERS-READ", "status": 200, "latencyMs": 12 },
    { "id": "SEC-ANON-DIRECT-BOOKING-INSERT", "status": 403, "latencyMs": 18 },
    { "id": "SEC-ANON-BOOK-SLOT-RPC", "status": 403, "latencyMs": 15 }
  ]
}
```
