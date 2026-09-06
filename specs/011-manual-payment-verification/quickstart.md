# Quickstart: Manual Payment Verification — End-to-End Validation

**Feature**: 011 | Prereqs: local stack running (`npx supabase start`, then `npx supabase db reset`), Docker DB container `supabase_db_church`.

## 1. Schema + RPC suites

```bash
npm run test:sql            # full suite; new proof suites must PASS with parsed TAP output
deno test --allow-env --allow-net supabase/functions/   # remaining function suites green
```

New suites prove: owner-submit allowed / non-owner denied (0 rows), wallet-without-image rejected, staff-only decisions, idempotent double-approve, reject→resubmit→approve lifecycle, expiry cancels booking with a PENDING proof attached and promotes waiting list.

## 2. Golden path (member → admin → confirmed)

1. **Book**: user portal (`test-apps/user.html`) → sign in as seeded member → book an open slot. Booking lands `PENDING_PAYMENT` with a 20-min lock.
2. **See payout details**: payment step shows the church's Vodafone Cash / InstaPay numbers (from `payout_channels`) with copyable values.
3. **Submit proof** (simulate transfer having happened): upload screenshot to the member prefix in `payment-proofs`, then call the submission RPC from the app screen. Screen confirms "بانتظار المراجعة". Booking stays `PENDING_PAYMENT`.
4. **Review**: admin portal (`test-apps/admin.html`, ADMIN account) → payments queue shows the proof with thumbnail + claimed fields.
5. **Verify against own statement** (manual step for reviewers): match reference + amount on the church wallet log.
6. **Approve**: one tap → proof APPROVED, payment PAID via existing procedure, booking → `AWAITING_CALL`; payment-received WhatsApp template enqueued (SENT or recorded-undelivered if provider unconfigured).
7. **Confirm by phone** (existing flow): admin confirms → `CONFIRMED`. Lifecycle identical to pre-011.

## 3. Rejection path

Reject the queued proof with the amount-mismatch reason → member sees the catalog Arabic sentence on their booking screen → resubmit corrected details before lock expiry → new PENDING proof appears; old one stays as REJECTED history.

## 4. Expiry composition

Book, submit nothing, wait past lock (or shrink interval in test fixture): cron cancels booking, seat frees, waiting list promotes. Repeat with a PENDING proof attached — same outcome; later approval attempt on the orphaned proof fails with the standard sentence.

## 5. Deletion verification

```bash
grep -ri "paymob" supabase/functions apps/mobile/lib apps/admin/lib supabase/config.toml   # zero hits
grep -rn "PAYMOB_" supabase/functions                                                      # zero env reads
npm run test:sql && deno test --allow-env --allow-net supabase/functions/
```

Historical migrations excepted. Both apps: `flutter analyze` + `flutter test` green; Arabic strings elsewhere unchanged.

## 6. Negative authorization spot-checks

Unauthenticated submit → `UNAUTHORIZED`; non-owner submit → `FORBIDDEN` (0 rows); USER-role approve/reject → `FORBIDDEN` (0 rows); anon storage read → empty/denied. All asserted inside registered suites (row-count semantics per AGENTS.md RLS Test Semantics).
