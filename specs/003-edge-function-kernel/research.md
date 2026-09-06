# Research: 003-edge-function-kernel

**Date**: 2026-08-16 · **Sources**: supabase.com/docs/guides/functions/auth (fetched live), repo conventions.md, AGENTS.md Locked Decisions, 2026-08-16 architecture review evidence.

## R1: Where auth verification lives — in-function seam, not platform flag

- **Decision**: All verification happens inside each function via the shared seam (`auth(req)`); `config.toml` sets `verify_jwt = false` explicitly for every function (webhook included), and the seam is the single enforcement point.
- **Rationale**: Supabase's current guidance (docs/guides/functions/auth, 2026) states `verify_jwt` is incompatible with the new JWT Signing Keys and that they "no longer implicitly force JWT verification, but instead suggest patterns and templates to handle this task" — users own the auth code. Owning it in one seam makes auth visible, testable, and uniform (the exact drift the review found: 4 gates, 4 semantics). The webhook needs `verify_jwt = false` anyway (Paymob calls carry no Supabase JWT); security-audit finding "no per-function verify_jwt blocks" is resolved by declaring it explicitly everywhere.
- **Alternatives considered**: (a) Rely on default platform `verify_jwt` — rejected: invisible to tests, deprecated direction, cannot express role gates (FR-002) or the signature-auth webhook; (b) per-function bespoke checks (status quo) — rejected: proven drift.

## R2: Verification API — `getUser` now, seam hides future `getClaims`

- **Decision**: The seam verifies via the auth server roundtrip (`supabase.auth.getUser(token)`-style), returning the user or a standard 401.
- **Rationale**: Works today with both legacy symmetric keys and the new asymmetric keys (server-side validation). Supabase's new `getClaims()` (local verification) requires the `SB_PUBLISHABLE_KEY` secret which is "not available by default in the Edge Functions environment" yet. The seam isolates the swap point so migrating to `getClaims` later touches one file.
- **Alternatives considered**: `jose` local JWKS verification (Supabase template) — rejected for now: adds dependency + key management the roundtrip avoids at current traffic; revisit if auth latency matters.

## R3: Error vocabulary

- **Decision**: One machine-readable shape and five stable codes: `UNAUTHORIZED` (401), `FORBIDDEN` (403), `BAD_REQUEST` (400), `UPSTREAM_ERROR` (502), `INTERNAL` (500). Shape: `{"error": "<CODE>", "message": "<human hint, optional>"}` with standard CORS headers.
- **Rationale**: Matches conventions.md's mandated `UPSTREAM_ERROR` 502 contract and the codes already most used in the codebase (`UNAUTHORIZED` offline-sync, `INTERNAL` paymob-checkout); replaces the plain-text `"unauthorized"` and `{success:false,error}` dialects.
- **Alternatives considered**: RFC 7807 problem+json — rejected: heavier than the mobile clients need; existing clients already parse `{"error": ...}`.

## R4: Outbox claim fallback — removed, not logged-only

- **Decision**: When the atomic outbox-claim RPC fails, the run aborts with an incident log; the non-atomic fallback query path is deleted (FR-009), making README's "atomic leasing, no duplicate messaging" claim true.
- **Rationale**: Silent fallback reintroduces the duplicate-send race the RPC was built to kill; the review caught `rpcErr` swallowed unlogged.
- **Alternatives considered**: Keep fallback + log — rejected: log lines don't stop double WhatsApp sends.

## R5: Paymob adapter surface

- **Decision**: One adapter exporting session acquisition (with token cache: reuse until `expires_in − 60s`), checkout, refund, and transaction status; single HMAC field-list definition shared by the webhook and imported by `e2e/book_pay_flow.mjs` (deletes the 5th re-implementation).
- **Rationale**: Token exchange byte-identical 3× today; refund currently inline in event-dispatcher; e2e drift breaks silently.
- **Alternatives considered**: Leave e2e copy — rejected: drift already the review's finding. (Scope note: refund stays manual-admin queue per ADR 0001; moving refund state into an RPC is review candidate #4, excluded.)

## R6: Test placement

- **Decision**: Shared-kernel suites live in `supabase/functions/_tests/` (the currently-empty directory); existing per-function `*_test.ts` suites stay in place and are updated to the seam.
- **Rationale**: Directory already announced as the intended seam; keeps shared behavior tests separate from per-function handler tests; satisfies SC-004.
- **Alternatives considered**: All tests per-function — rejected: shared behavior would be re-tested 9× or not at all.

## Resolved NEEDS CLARIFICATION

None were raised in the spec; R1–R6 resolve the technical decisions the plan phase required.
