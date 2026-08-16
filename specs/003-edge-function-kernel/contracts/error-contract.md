# Contract: Unified Error Response

**Audience**: mobile app, admin web app, e2e scripts. **Applies to**: every edge-function endpoint.

## Shape

```json
{
  "error": "UNAUTHORIZED | FORBIDDEN | BAD_REQUEST | UPSTREAM_ERROR | INTERNAL",
  "message": "optional short human hint, safe for display"
}
```

- HTTP status per code: 401 / 403 / 400 / 502 / 500 (see data-model.md).
- All responses (success and error) carry the standard CORS headers.
- No endpoint may return a different error shape, plain-text error, or internal details (stack, SQL, provider payloads).

## Migration notes

| Old dialect (removed) | Site | Becomes |
|---|---|---|
| `{"error":"INTERNAL"}` 500 | paymob-checkout, event-dispatcher, reconcile-payments, youtube-expiry | `INTERNAL` |
| `{"error":"Internal Server Error"}` | offline-sync | `INTERNAL` |
| `{"success":false,"error":...}` | diagnostic-engine | standard error shape |
| plain text `unauthorized` | analytics-export | `UNAUTHORIZED` 401 JSON |
| inline error strings (`"Sync failed"`, `"Invalid payload..."`) | offline-sync et al. | `INTERNAL` / `BAD_REQUEST` |

Clients keep working during migration only if they already parse `{"error": ...}` — the dominant dialect; string-matchers must move to code equality (tracked as client follow-up, out of scope).
