-- 0066_manual_payment_foundations.sql
-- 011 Phase 2: manual payment rail foundations (ADR 0003)
-- payment_channel enum, payment_proofs, payout_channels, storage bucket
-- `payment-proofs`, ownership helpers, idempotent wallet-channel seed.

-- ---------------------------------------------------------------------------
-- 1. Enum
-- ---------------------------------------------------------------------------
create type public.payment_channel as enum ('VODAFONE_CASH', 'INSTAPAY', 'CASH');

-- ---------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------
create table public.payment_proofs (
  id bigint generated always as identity primary key,
  booking_id bigint not null references public.bookings(id),
  payment_id bigint references public.payments(id),
  channel public.payment_channel not null,
  sender_phone text not null,
  reference_number text not null,
  amount_claimed int not null check (amount_claimed > 0),
  image_path text,
  status text not null default 'PENDING'
    check (status in ('PENDING', 'APPROVED', 'REJECTED')),
  reject_reason_code text,
  collector_note text,
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

create unique index payment_proofs_one_pending_per_booking_idx
  on public.payment_proofs (booking_id) where status = 'PENDING' and deleted_at is null;
create index payment_proofs_booking_idx on public.payment_proofs (booking_id);

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

-- ---------------------------------------------------------------------------
-- 3. Ownership helper (definer so policies never recurse through bookings RLS)
-- ---------------------------------------------------------------------------
create or replace function public.is_booking_owner(p_booking_id bigint)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
stable
as $$
begin
  return exists (
    select 1 from public.bookings b
    where b.id = p_booking_id and b.user_id = auth.uid()
  );
end $$;

revoke all on function public.is_booking_owner(bigint) from public, anon, authenticated;
grant execute on function public.is_booking_owner(bigint) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. RLS — enable before policies (AGENTS.md guard)
-- ---------------------------------------------------------------------------
alter table public.payment_proofs enable row level security;
alter table public.payout_channels enable row level security;

drop policy if exists "Members read proofs of own bookings" on public.payment_proofs;
create policy "Members read proofs of own bookings"
  on public.payment_proofs
  for select
  to authenticated
  using (
    tenant_id = public.tenant_id()
    and public.is_booking_owner(booking_id)
  );

drop policy if exists "Admins read all payment proofs" on public.payment_proofs;
create policy "Admins read all payment proofs"
  on public.payment_proofs
  for select
  to authenticated
  using (
    tenant_id = public.tenant_id()
    and public.is_admin()
  );

-- Proof writes happen only inside SECURITY DEFINER RPCs; keep client DML off.
-- anon keeps SELECT (house posture) — RLS yields zero rows without a policy.
revoke insert, update, delete on public.payment_proofs from anon, authenticated;
grant select on public.payment_proofs to authenticated, anon;

grant usage, select on sequence public.payment_proofs_id_seq to authenticated;

drop policy if exists "Authenticated reads payout channels" on public.payout_channels;
create policy "Authenticated reads payout channels"
  on public.payout_channels
  for select
  to authenticated
  using (tenant_id = public.tenant_id());

drop policy if exists "Super admins maintain payout channels" on public.payout_channels;
create policy "Super admins maintain payout channels"
  on public.payout_channels
  for update
  to authenticated
  using (
    tenant_id = public.tenant_id()
    and public.is_super_admin()
  )
  with check (
    tenant_id = public.tenant_id()
    and public.is_super_admin()
  );

revoke insert, delete on public.payout_channels from anon, authenticated;
grant select on public.payout_channels to authenticated, anon;
grant update on public.payout_channels to authenticated;

-- service_role full access (edge seams + tests)
grant select, insert, update, delete on public.payment_proofs, public.payout_channels to service_role;

-- ---------------------------------------------------------------------------
-- 5. Storage bucket `payment-proofs` (private; {tenant}/{booking}/{proof}.ext)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'payment-proofs',
  'payment-proofs',
  false,
  5242880, -- 5MB per screenshot
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

do $$
begin
  alter table storage.objects enable row level security;
exception
  when insufficient_privilege then null;
end $$;

-- Path parser guard shared by the member object policies
create or replace function public.proof_object_booking(p_name text)
returns bigint
language sql
immutable
as $$
  select case when p_name ~ '^[0-9]+/[0-9]+/[^/]+$'
    then split_part(p_name, '/', 2)::bigint end
$$;

revoke all on function public.proof_object_booking(text) from public, anon, authenticated;
grant execute on function public.proof_object_booking(text) to authenticated, service_role;

drop policy if exists "Members upload own booking proof images" on storage.objects;
create policy "Members upload own booking proof images"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'payment-proofs'
    and name like public.tenant_id()::text || '/%'
    and public.is_booking_owner(public.proof_object_booking(name))
  );

drop policy if exists "Members read own booking proof images" on storage.objects;
create policy "Members read own booking proof images"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'payment-proofs'
    and name like public.tenant_id()::text || '/%'
    and public.is_booking_owner(public.proof_object_booking(name))
  );

drop policy if exists "Members delete proof while booking pending" on storage.objects;
create policy "Members delete proof while booking pending"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'payment-proofs'
    and name like public.tenant_id()::text || '/%'
    and public.is_booking_owner(public.proof_object_booking(name))
    and exists (
      select 1 from public.bookings b
      where b.id = public.proof_object_booking(name)
        and b.status = 'PENDING_PAYMENT'
        and b.user_id = auth.uid()
    )
  );

drop policy if exists "Admins read all payment proof images" on storage.objects;
create policy "Admins read all payment proof images"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'payment-proofs'
    and public.is_admin()
  );

-- ---------------------------------------------------------------------------
-- 6. Idempotent seed: church wallet landing details (super-admin editable)
-- ---------------------------------------------------------------------------
insert into public.payout_channels (channel, display_name_ar, account_number, holder_name)
values
  ('VODAFONE_CASH', 'فودافون كاش', '01000000000', 'الكنيسة'),
  ('INSTAPAY', 'إنستاباي', '01011112222', 'الكنيسة')
on conflict (channel) do update set
  display_name_ar = excluded.display_name_ar,
  account_number = excluded.account_number,
  holder_name = excluded.holder_name,
  updated_at = now();
