# Data Model: 003-edge-function-kernel

**No database changes.** This feature is behavior-preserving on storage (FR-013). All entities below are conceptual/contractual, not new tables.

## Error Code

| Code | HTTP | Meaning | Client action |
|------|------|---------|---------------|
| `UNAUTHORIZED` | 401 | Missing/malformed/invalid/expired token | Re-authenticate |
| `FORBIDDEN` | 403 | Valid identity, insufficient role | Hide/deny feature |
| `BAD_REQUEST` | 400 | Malformed payload/params | Fix input |
| `UPSTREAM_ERROR` | 502 | Payment gateway failed or unparseable | Retry later |
| `INTERNAL` | 500 | Unexpected failure; detail logged server-side only | Retry / report |

Validation: code list is closed; responses use `{"error": CODE, "message": string?}`.

## Protected Endpoint (registry)

Each of the 9 edge functions, classified:

| Function | Auth | Role gate |
|----------|------|-----------|
| paymob-checkout | Bearer | any authenticated |
| paymob-webhook | Paymob HMAC signature | — (never user tokens) |
| event-dispatcher | service/cron context | — |
| reconcile-payments | service/cron context | — |
| youtube-expiry | service/cron context | — |
| offline-sync | Bearer | any authenticated |
| analytics-export | Bearer | staff (ADMIN\|PRIEST\|SUPER_ADMIN) |
| otp-sms | Bearer | any authenticated |
| diagnostic-engine | Bearer | staff |

Rules: bearer endpoints reject before business logic (FR-001); staff endpoints additionally enforce role from trusted account metadata (FR-002); service-context functions reject external bearer-less calls per their deployment wiring.

## Gateway Operation

Categories: `session`, `checkout`, `refund`, `status`. Shared failure policy: timeout → `UPSTREAM_ERROR`; non-2xx → `UPSTREAM_ERROR`; 2xx with unparseable body → `UPSTREAM_ERROR` + payment marked `FAILED` where a payment row exists (FR-006/007). Session token cached until `expires_in − 60s`.

## Outbox Lease

Exclusive right for one run to claim a message batch. Granted only via the atomic claim RPC. Lease acquisition failure ⇒ run aborts with incident log (FR-009); no fallback grant path exists.
