# Contracts: RPC Surface

**Feature**: 011 | Frozen error codes: `UNAUTHORIZED | FORBIDDEN | BAD_REQUEST | UPSTREAM_ERROR | INTERNAL` — every failure below returns `{"error": CODE, "message_ar": <catalog sentence>}` via the standard helper; clients display `message_ar` only.

All three procedures: `SECURITY DEFINER`, `SET search_path = ''`, audit-trigger covered, REVOKE ALL from `PUBLIC, anon, authenticated` before grants.

## `submit_payment_proof`

```sql
submit_payment_proof(
  p_booking_id   bigint,
  p_channel      public.payment_channel,   -- VODAFONE_CASH | INSTAPAY | CASH
  p_sender_phone text,
  p_reference    text,
  p_amount       int,
  p_image_path   text                      -- required iff channel <> 'CASH'
) returns bigint                               -- proof id
```

- **Grants**: `authenticated` only.
- **Guards (in order)**: booking exists & not deleted & tenant matches → caller owns booking (`FORBIDDEN`) → booking status = `PENDING_PAYMENT` (`BAD_REQUEST`) → channel/image consistency (`BAD_REQUEST`) → no existing PENDING proof (`BAD_REQUEST`) → image object exists under caller's prefix for wallet channels (`BAD_REQUEST`).
- **Writes**: snapshot payment row via existing seam procedure `create_pending_payment(p_booking_id, p_amount, null)`; insert proof `PENDING`.
- **Returns**: new proof id.

## `approve_payment_proof`

```sql
approve_payment_proof(
  p_proof_id      bigint,
  p_collector_note text default null        -- CASH only
) returns jsonb                              -- {"booking_id":…, "payment_id":…}
```

- **Grants**: service_role + in-RPC tier gate `users.role IN ('ADMIN','SUPER_ADMIN')` fail-closed (`FORBIDDEN`).
- **Guards**: proof exists & PENDING (row-locked `FOR UPDATE`; not-PENDING → idempotent denial `BAD_REQUEST`) → owning booking still `PENDING_PAYMENT` (else existing stale-booking semantics apply untouched).
- **Writes**: proof → `APPROVED` (+reviewer/time/note); executes **existing** `apply_payment(p_payment_id)` unchanged — including its stale/cancelled → `REFUND_PENDING` behavior.
- **Idempotency**: second call on same proof never re-transitions (status guard), concurrent approve-vs-expiry resolves inside one transaction.

## `reject_payment_proof`

```sql
reject_payment_proof(
  p_proof_id    bigint,
  p_reason_code text                          -- must be a frozen catalog code
) returns void
```

- **Grants**: same tier gate as approve.
- **Guards**: proof exists & PENDING (`BAD_REQUEST` otherwise) → reason code ∈ catalog (`BAD_REQUEST`).
- **Writes**: proof → `REJECTED` + reason + reviewer/time. **Zero financial writes.**

## `mark_cash_received`

```sql
mark_cash_received(
  p_booking_id    bigint,
  p_amount        int,
  p_collector_note text default null
) returns jsonb                                -- {"proof_id":…, "booking_id":…, "payment_id":…}
```

- **Grants**: service_role + in-RPC tier gate `users.role IN ('ADMIN','SUPER_ADMIN')` fail-closed (`FORBIDDEN`).
- **Guards**: booking exists & `PENDING_PAYMENT` (`BAD_REQUEST`) → no PENDING proof already awaiting (`BAD_REQUEST`).
- **Writes**: single transaction — inserts a CASH proof row already `APPROVED` (no image, collector note + reviewer/time), snapshots payment via `create_pending_payment`, executes existing `apply_payment`.
- **Rationale**: one round-trip for the in-person path; identical financial semantics to wallet approval by construction.

## Storage contract

Bucket `payment-proofs` (private). Object path `{tenant_id}/{booking_id}/{proof_id}.{ext}`.

| Role | Policies on `storage.objects` |
|---|---|
| member (owner) | SELECT/INSERT objects where prefix matches own booking and booking is theirs (join via definer helper); DELETE only while booking `PENDING_PAYMENT` |
| ADMIN / SUPER_ADMIN | SELECT all under bucket (`public.is_admin()`) |
| anon | nothing |

Guard compliance: explicit `ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;`, granular DML grants to `authenticated`, `TO authenticated` targeting, no public bucket flag.

## App repository contracts (`Either<Failure, T>`)

```dart
// mobile — BookingRepository extension
Future<Either<Failure, PaymentProof>> submitPaymentProof(SubmitProofInput input);
// admin — PaymentsAdminRepository additions
Future<Either<Failure, List<PaymentProofReview>>> listPendingProofs();
Future<Either<Failure, void>> approveProof(int proofId, {String? collectorNote});
Future<Either<Failure, void>> rejectProof(int proofId, String reasonCode);
Future<Either<Failure, List<PayoutChannel>>> listPayoutChannels();     // shared read
Future<Either<Failure, void>> upsertPayoutChannel(PayoutChannel c);    // SUPER_ADMIN gate
```

Zero raw `PostgrestException` leaks; fakes are slot/proof-aware per AGENTS.md Direct Repository Testing rule.
