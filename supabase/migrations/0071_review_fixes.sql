-- ==============================================================================
-- 0071_review_fixes.sql
-- 011 post-review hardening (qodo PR#9 findings):
--   1) payout_channels: is_active gate (placeholder seeds ship inactive) and
--      per-tenant (tenant_id, channel) uniqueness instead of global
--   2) approve_payment_proof: refuse proofs on bookings no longer PENDING_PAYMENT
--   3) reject_payment_proof: void the linked CREATED payment (ledger hygiene)
--   4) transition_booking_status: close NULL-uid fail-open in the caller gate;
--      non-admin owners may only CANCEL (the gateway-era apply_payment escape
--      hatch is dead now that approvals go through approve_payment_proof)
--   5) apply_payment / emergency_override: stop enqueueing PAYMOB_REFUND outbox
--      events — the consumer was deleted with the Paymob stack (ADR 0003);
--      refunds are manual/offline
--   6) storage admin read policy: enforce tenant path prefix like table RLS
-- Forward-only: applied migrations are never modified.
-- ==============================================================================

-- ---------------------------------------------------------------------------
-- 1. payout_channels: is_active + per-tenant uniqueness
-- ---------------------------------------------------------------------------
alter table public.payout_channels
  add column if not exists is_active boolean not null default false;

alter table public.payout_channels
  drop constraint if exists payout_channels_channel_key;

-- Seed idempotency target moves to the composite key; existing rows keep
-- their identity while a second tenant can now configure its own channels.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.payout_channels'::regclass
      and conname = 'payout_channels_tenant_channel_key'
  ) then
    alter table public.payout_channels
      add constraint payout_channels_tenant_channel_key unique (tenant_id, channel);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. approve_payment_proof: booking must still be awaiting payment
-- ---------------------------------------------------------------------------
create or replace function public.approve_payment_proof(
  p_proof_id bigint,
  p_collector_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_proof public.payment_proofs;
  v_booking public.bookings;
begin
  if v_user is null then
    raise exception 'UNAUTHORIZED' using errcode = '28000';
  end if;

  select role into v_role from public.users where id = v_user;
  if v_role is null or v_role not in ('ADMIN', 'SUPER_ADMIN') then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select * into v_proof from public.payment_proofs
    where id = p_proof_id and tenant_id = public.tenant_id()
    for update;
  if v_proof.id is null or v_proof.status <> 'PENDING' then
    raise exception 'BAD_REQUEST';
  end if;

  if p_collector_note is not null and v_proof.channel <> 'CASH' then
    raise exception 'BAD_REQUEST';
  end if;

  select * into v_booking from public.bookings
    where id = v_proof.booking_id and tenant_id = public.tenant_id()
    for update;
  -- Expired/cancelled bookings keep their proof visible but undecidable;
  -- the seat is gone, so approval would silently strand money state.
  if v_booking.id is null or v_booking.status <> 'PENDING_PAYMENT' then
    raise exception 'BAD_REQUEST';
  end if;

  update public.payment_proofs
  set status = 'APPROVED',
      collector_note = coalesce(p_collector_note, collector_note),
      reviewed_by = v_user,
      reviewed_at = now(),
      updated_at = now()
  where id = v_proof.id;

  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (v_user, 'approve_payment_proof', 'payment_proofs', v_proof.id,
          jsonb_build_object('booking_id', v_proof.booking_id, 'payment_id', v_proof.payment_id,
                             'channel', v_proof.channel, 'amount_claimed', v_proof.amount_claimed));

  if v_proof.payment_id is not null then
    perform public.apply_payment(v_proof.payment_id);
  end if;

  return jsonb_build_object(
    'booking_id', v_proof.booking_id,
    'payment_id', v_proof.payment_id
  );
end $$;

revoke all on function public.approve_payment_proof(bigint, text) from public, anon, authenticated;
grant execute on function public.approve_payment_proof(bigint, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. reject_payment_proof: void the pending payment snapshot
-- ---------------------------------------------------------------------------
create or replace function public.reject_payment_proof(
  p_proof_id bigint,
  p_reason_code text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_proof public.payment_proofs;
begin
  if v_user is null then
    raise exception 'UNAUTHORIZED' using errcode = '28000';
  end if;

  select role into v_role from public.users where id = v_user;
  if v_role is null or v_role not in ('ADMIN', 'SUPER_ADMIN') then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_reason_code is null or not exists (
    select 1 from public.error_messages where code = p_reason_code
  ) then
    raise exception 'BAD_REQUEST';
  end if;

  select * into v_proof from public.payment_proofs
    where id = p_proof_id and tenant_id = public.tenant_id()
    for update;
  if v_proof.id is null or v_proof.status <> 'PENDING' then
    raise exception 'BAD_REQUEST';
  end if;

  update public.payment_proofs
  set status = 'REJECTED',
      reject_reason_code = p_reason_code,
      reviewed_by = v_user,
      reviewed_at = now(),
      updated_at = now()
  where id = v_proof.id;

  -- Each submission snapshots its own CREATED payment; a rejection means that
  -- snapshot will never be collected, so void it instead of accumulating
  -- active-looking ledger rows.
  update public.payments
  set status = 'FAILED',
      updated_at = now()
  where id = v_proof.payment_id
    and status = 'CREATED';

  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (v_user, 'reject_payment_proof', 'payment_proofs', v_proof.id,
          jsonb_build_object('booking_id', v_proof.booking_id, 'reason_code', p_reason_code));
end $$;

revoke all on function public.reject_payment_proof(bigint, text) from public, anon, authenticated;
grant execute on function public.reject_payment_proof(bigint, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. transition_booking_status: fail-closed caller gate; owners may only cancel
-- ---------------------------------------------------------------------------
create or replace function public.transition_booking_status(
  p_booking_id bigint,
  p_new_status public.booking_status,
  p_action text,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
) returns public.bookings language plpgsql security definer set search_path = public as $$
declare
  v_book public.bookings;
  v_old_status public.booking_status;
  v_role text := public.current_user_role();
  v_is_service boolean := coalesce(auth.role(), '') = 'service_role' or current_user = 'service_role';
begin
  select * into v_book from public.bookings where id = p_booking_id for update;
  if v_book is null then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_book.status = p_new_status then return v_book; end if;

  -- SECURITY DEFINER must never widen access: re-assert gates here.
  -- Allowed callers: admin tier, the booking owner, or the service role.
  -- coalesce guards the SQL-NULL hole: an absent JWT used to make the whole
  -- NOT(...) evaluate NULL and skip the raise.
  if not (
    v_is_service
    or public.is_admin()
    or (v_book.user_id is not null and v_book.user_id = auth.uid())
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- Regular users can only cancel their own bookings. Payment advancement is
  -- staff-only via approve_payment_proof/mark_cash_received -> apply_payment.
  if not (v_is_service or public.is_admin()) then
    if p_new_status <> 'CANCELLED' then
      raise exception 'FORBIDDEN: users can only cancel bookings' using errcode = '42501';
    end if;
  end if;

  v_old_status := v_book.status;
  update public.bookings
     set status = p_new_status,
         locked_until = case when p_new_status = 'PENDING_PAYMENT' then locked_until else null end,
         updated_at = now()
   where id = p_booking_id
   returning * into v_book;

  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (auth.uid(), p_action, 'bookings', p_booking_id,
          jsonb_build_object('old_status', v_old_status, 'new_status', p_new_status, 'reason', p_reason, 'slot_id', v_book.slot_id) || p_metadata);
  return v_book;
end $$;

REVOKE ALL ON FUNCTION public.transition_booking_status(bigint, public.booking_status, text, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.transition_booking_status(bigint, public.booking_status, text, text, jsonb)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5a. apply_payment: stale branch no longer enqueues refund events.
--     The PAYMOB_REFUND consumer was deleted with the Paymob stack (ADR 0003);
--     refunds are reconciled manually against church records.
-- ---------------------------------------------------------------------------
create or replace function public.apply_payment(p_payment_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_pay public.payments;
  v_book public.bookings;
  v_phone text;
begin
  select * into v_pay from public.payments where id = p_payment_id for update;
  if v_pay is null then raise exception 'PAYMENT_NOT_FOUND'; end if;
  if v_pay.status = 'PAID' then return; end if;
  update public.payments set status = 'PAID' where id = v_pay.id;
  if v_pay.booking_id is not null then
    select * into v_book from public.bookings where id = v_pay.booking_id for update;
    if v_book is null
       or v_book.status <> 'PENDING_PAYMENT'
       or v_book.locked_until <= now() then
      update public.payments set status = 'REFUND_PENDING' where id = v_pay.id;
      return;
    end if;
    update public.bookings set paid_amount = v_pay.amount where id = v_book.id;
    v_book := public.transition_booking_status(v_book.id, 'AWAITING_CALL', 'apply_payment', null, jsonb_build_object('payment_id', v_pay.id));
    select phone into v_phone from public.users where id = v_book.user_id;
    if v_phone is not null and not exists (
      select 1 from public.event_outbox
      where handler_type = 'WHATSAPP'
        and (payload->>'booking_id' = v_book.id::text or payload->'params'->>'booking_id' = v_book.id::text)
        and payload->>'template_name' = 'booking_payment_received'
    ) then
      insert into public.event_outbox (handler_type, payload)
      values ('WHATSAPP', jsonb_build_object('phone', v_phone, 'template_name', 'booking_payment_received',
                                             'params', jsonb_build_object('booking_id', v_book.id, 'amount', v_pay.amount)));
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 5b. emergency_override: refund requests stay manual (no outbox event)
-- ---------------------------------------------------------------------------
create or replace function public.emergency_override(
  p_booking_id bigint,
  p_new_slot_id bigint,
  p_refund boolean default false
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.current_user_role();
  v_book public.bookings;
  v_phone text;
  v_new public.bookings;
  v_slot_new public.service_slots;
begin
  if v_role not in ('PRIEST','ADMIN','SUPER_ADMIN') then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
  select * into v_book from public.bookings where id = p_booking_id for update;
  if v_book is null then raise exception 'BOOKING_NOT_FOUND'; end if;
  if not exists (select 1 from public.service_slots where id = p_new_slot_id and status <> 'CLOSED' and starts_at > now())
  then raise exception 'SLOT_UNAVAILABLE'; end if;
  select phone into v_phone from public.users where id = v_book.user_id;
  perform public.transition_booking_status(p_booking_id, 'RESCHEDULED', 'emergency_reschedule', null, jsonb_build_object('new_slot_id', p_new_slot_id, 'refund', p_refund));
  begin
    -- capacity-aware reschedule: lock the target slot and count active bookings
    select * into v_slot_new from public.service_slots where id = p_new_slot_id for update;
    if v_slot_new is null or v_slot_new.status = 'CLOSED' then raise exception 'NEW_SLOT_TAKEN'; end if;
    if public.active_booking_count(p_new_slot_id, true) >= v_slot_new.capacity then raise exception 'NEW_SLOT_TAKEN'; end if;
    insert into public.bookings (slot_id, user_id, status, created_by, notes, tenant_id)
    values (p_new_slot_id, v_book.user_id, 'CONFIRMED', 'employee', 'rescheduled by emergency_override', public.tenant_id())
    returning * into v_new;
  end;
  if v_phone is not null then
    insert into public.event_outbox (handler_type, payload)
    values ('WHATSAPP', jsonb_build_object('phone', v_phone, 'template_name', 'booking_apology', 'params', jsonb_build_object('booking_id', p_booking_id)));
    insert into public.event_outbox (handler_type, payload)
    values ('WHATSAPP', jsonb_build_object('phone', v_phone, 'template_name', 'booking_rescheduled',
                                           'params', jsonb_build_object('old_slot', v_book.slot_id, 'new_slot', p_new_slot_id)));
  end if;
  -- Refund flag lands in audit_log only; actual refunds are manual per ADR 0003.
  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (auth.uid(), 'emergency_override', 'bookings', p_booking_id,
          jsonb_build_object('new_booking_id', v_new.id, 'new_slot_id', p_new_slot_id, 'refund', p_refund));
  return v_new.id;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Storage: admins read receipts within their own tenant only
-- ---------------------------------------------------------------------------
drop policy if exists "Admins read all payment proof images" on storage.objects;
create policy "Admins read all payment proof images"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'payment-proofs'
    and name like public.tenant_id()::text || '/%'
    and public.is_admin()
  );
