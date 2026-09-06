# Contract: Shared Kernel Module Interfaces

**Audience**: edge-function handlers (the 9 consumers) and the Deno test suites. File paths are the delivery surface for the seam (research R5/R6).

## `functions/_shared/http.ts`

```ts
// Identity gate. Verifies bearer token via auth server (research R2).
// Returns Response (standard error, do-not-continue) or the verified user.
auth(req: Request, opts?: { requireStaff?: boolean }): Promise<Response | AuthUser>

// Single responder. Owns CORS headers + error shape (contracts/error-contract.md).
respond(status: number, code: ErrorCode, message?: string, body?: unknown): Response
```

Rules: handlers call `auth()` first; on Response return it verbatim (FR-001/002). All exits go through `respond()` (FR-004/005, FR-012). `cors.ts` folds in here; no separate constant import.

## `functions/_shared/paymob.ts`

```ts
// Gateway adapter. Single implementation of session/checkout/refund/status (FR-006).
createPaymob(deps: { apiKey: string; baseUrl?: string; fetch?: FetchLike }): PaymobClient

interface PaymobClient {
  session(): Promise<GatewayToken>            // cached until expires_in − 60s
  checkout(input: CheckoutInput): Promise<CheckoutResult>
  refund(input: RefundInput): Promise<RefundResult>      // no auto-fire; queue only (ADR 0001)
  orderStatus(id: string): Promise<OrderStatus>
  hmacFields(): string[]                      // single HMAC field-list source
}
```

Failure policy: every gateway call returns typed failure `UPSTREAM_ERROR`; never throws raw parse errors to handlers; callers mark payment `FAILED` via the shared cleanup helper (FR-008) — one function, replacing the 8 copies in paymob-checkout.

## `e2e/book_pay_flow.mjs`

Imports the HMAC field list from the adapter source (single source of truth); deletes its local `txnFields` copy.

## `supabase/config.toml`

Explicit per-function block for all 9 functions; `verify_jwt = false` everywhere (research R1) — enforcement lives in the seam. Webhook (`paymob-webhook`) authenticates by Paymob HMAC only (FR-003).
