# Quickstart: Validate 003-edge-function-kernel

**Prereqs**: (1) The three audit blockers landed on `main` (secrets fallbacks stripped from `diagnostic_engine/deno_engine.ts`; 0044 in-place edit reverted into a forward migration; NULL-role bypass + missing REVOKE fixed in `purchase_video`). (2) Local stack running: `npx supabase start`.

## 1. Shared-kernel unit suites (SC-004)

```bash
cd supabase
deno test --allow-env --allow-net functions/_tests/
```

Expected: suites for `auth` (valid / missing / malformed / expired / insufficient-role — 5 outcomes), `respond` (shape + CORS), `paymob` (fake gateway: session cache, checkout, refund, status, unparseable-response → UPSTREAM_ERROR) all pass.

## 2. Per-function suites (FR-013 behavior preserved)

```bash
deno test --allow-env --allow-net functions/paymob-checkout/ functions/paymob-webhook/ functions/event-dispatcher/ functions/offline-sync/ functions/reconcile-payments/ functions/youtube-expiry/ functions/analytics-export/ functions/otp-sms/
```

Expected: pass, with handlers importing `_shared/http.ts` + `_shared/paymob.ts`; zero local copies of token exchange / verification / error shaping (grep check below).

## 3. Auth sweep — every protected endpoint (SC-001)

For each bearer endpoint (paymob-checkout, offline-sync, analytics-export, otp-sms, diagnostic-engine) with the local stack's function URL:

```bash
for tok in "" "Bearer garbage" "Bearer expired.jwt.here" "Bearer <valid>"; do
  curl -s -o /dev/null -w "%{http_code} " -H "Authorization: $tok" "$FUNC_URL"
done
# expect: 401 401 401 2xx-or-403(staff endpoints)  — identical across all endpoints
```

Webhook check: POST to paymob-webhook with a user JWT → must NOT authenticate as a user (HMAC path only).

## 4. SQL regression (SC-006)

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/run_all.sql
```

Expected: full suite passes unchanged.

## 5. End-to-end payment flow (SC-003, SC-006)

```bash
node supabase/e2e/book_pay_flow.mjs   # now imports shared hmacFields()
```

Expected: book → checkout → webhook → paid, identical outcomes to pre-refactor.

## 6. Credential + duplication scans (SC-002, SC-005)

```bash
# no hardcoded secrets/fallbacks
grep -rn "supabase.co\"\|eyJhbGciOi\|test_hmac_key" supabase/functions/ diagnostic_engine/ | grep -v test
# gateway token exchange defined exactly once
grep -rn "auth/tokens" supabase/functions/ | wc -l   # expect 1 (in _shared/paymob.ts)
# error dialects gone
grep -rn "Internal Server Error\|success:false" supabase/functions/ | wc -l   # expect 0
```

Expected: all greps clean (SC-005: 0 hits; SC-003: 1 definition).
