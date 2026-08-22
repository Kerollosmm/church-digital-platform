# Data Model: Manual Payment Verification

**Feature**: 011 | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

Existing tables referenced with exact shipped columns (source: `migrations/0001_init_schema.sql`; additive-only territory respected — no existing table gains or loses a column).

## New Types

```sql
create type public.payment_channel as enum ('VODAFONE_CASH', 'INSTAPAY', 'CASH');
```

Synced into `docs/superpowers/plans/conventions.md` §Enums (done in this phase). No existing enum changes.

## New Tables

### `public.payment_proofs`

The member's payment claim; many per booking, at most one `PENDING`.

```sql
create table public.payment_proofs (
  id bigint generated always as identity primary key,
  booking_id bigint not null references public.bookings(id),
  payment_id bigint references public.payments(id),      -- snapshot row from create_pending_payment
  channel public.payment_channel not null,
  sender_phone text not null,                            -- member's wallet number (CASH: collector contact)
  reference_number text not null,                        -- wallet transfer ref (CASH: receipt/talab no.)
  amount_claimed int not null check (amount_claimed > 0),
  image_path text,                                       -- storage path; null only when channel = 'CASH'
  status text not null default 'PENDING'
    check (status in ('PENDING', 'APPROVED', 'REJECTED')),
  reject_reason_code text,                               -- frozen catalog code; set only on REJECTED
  collector_note text,                                   -- CASH only: who collected
  reviewed_by uuid references public.users(id),
  reviewed_at timestamptz,
  tenant_id bigint not null default public.tenant_id(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint payment_proofs_image_required
    check ((channel = 'CASH') or (image_path is not null)),
  constraint payment_proofs_cash_no_image
    check ((channel <> 'CASH') or (image_path is null)),
  constraint payment_proofs_reject_reason
    check ((status <> 'REJECTED') or (reject_reason_code is not null))
);

-- at most one awaiting-review proof per booking
create unique index payment_proofs_one_pending_per_booking_idx
  on public.payment_proofs (booking_id) where status = 'PENDING' and deleted_at is null;
```

**Identity sequence**: `GRANT USAGE, SELECT ON SEQUENCE public.payment_proofs_id_seq TO authenticated;` (AGENTS.md Identity Sequences rule).

### `public.payout_channels`

What the church publishes for members to pay into.

```sql
create table public.payout_channels (
  id bigint generated always as identity primary key,
  channel public.payment_channel not null unique,
  display_name_ar text not null,
  account_number text not null,
  holder_name text not null,
  tenant_id bigint not null default public.tenant_id(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

Seed (idempotent `on conflict (channel) do update`): one `VODAFONE_CASH` row, one `INSTAPAY` row. `CASH` needs no row.

## RLS & Grants (guard rules applied)

- `ALTER TABLE public.payment_proofs ENABLE ROW LEVEL SECURITY;` before any policy; same for `payout_channels`.
- **payment_proofs**: member policies target `TO authenticated` with ownership via booking join (`booking.user_id = auth.uid()`) plus tenant check; admin read-all policy includes `public.is_admin()`; all mutations of financial columns flow through RPCs, so table-level `INSERT/UPDATE` stays revoked from clients (service_role only) — the RPCs run definer-side.
- **payout_channels**: `SELECT` to authenticated; `UPDATE` policy requires super-admin tier (`users.role = 'SUPER_ADMIN'` via fail-closed helper); no client INSERT/DELETE.
- Granular DML grants only; `REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon, authenticated` before each RPC grant.

## RPC Surface (contracts: [contracts/rpc-contracts.md](contracts/rpc-contracts.md))

| RPC | Caller | Writes |
|---|---|---|
| `submit_payment_proof(p_booking_id, p_channel, p_sender_phone, p_reference, p_amount, p_image_path)` | booking owner | `payment_proofs` PENDING row + `create_pending_payment` snapshot |
| `approve_payment_proof(p_proof_id, p_collector_note default null)` | ADMIN / SUPER_ADMIN | proof → APPROVED; executes existing `apply_payment` |
| `reject_payment_proof(p_proof_id, p_reason_code)` | ADMIN / SUPER_ADMIN | proof → REJECTED + reason; zero financial writes |

## State Machines

### Proof lifecycle (new)

```text
            submit (owner, wallet w/ image, cash w/o)
  [none] ──────────────────────────────▶ PENDING ──approve (staff)──▶ APPROVED (terminal)
                                            │
                                            └──reject (staff, reason)──▶ REJECTED (terminal;
                                                                             resubmit creates NEW row)
```

### Booking machine (unchanged, reference)

```text
PENDING_PAYMENT ──approve_payment_proof→ apply_payment ──▶ AWAITING_CALL ──admin call──▶ CONFIRMED ──▶ COMPLETED
      │
      └──expire_stale_bookings (cron, 1 min)──▶ CANCELLED (seat freed, waiting list promoted)
```

### Payment statuses (unchanged, reference)

`CREATED` at submission snapshot → `PAID` via `apply_payment` on approval; stale/cancelled booking at approval → `REFUND_PENDING` (existing 0012 semantics; manual refund procedure documented for admins).

## Validation Rules

| Rule | Enforcement |
|---|---|
| Wallet proofs carry an image; CASH never does | table CHECKs above + RPC re-validation |
| Only booking owner submits | RPC ownership check (fail-closed `FORBIDDEN`) |
| Only staff decide; double-approve idempotent | RPC tier gate + `status = 'PENDING'` guard row-locked in transaction |
| Amount positive integer (EGP piasters-free ints, matching `payments.amount int`) | CHECK + RPC |
| One PENDING proof per booking | unique partial index |
| Rejected proofs always carry a frozen catalog code | CHECK + RPC parameter validation |
| Expiry wins races deterministically | `apply_payment` existing transactional status guards (proven by 0064-class tests) |
