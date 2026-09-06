-- 0068_payment_decision_rpcs.sql
-- 011 US2: Staff-only payment proof decision RPCs (approve_payment_proof, reject_payment_proof).
-- Implements staff tier gates, FOR UPDATE locking, idempotent status transitions,
-- catalog reason verification, and delegation to apply_payment.

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select public.current_user_role() in ('ADMIN', 'SUPER_ADMIN')
$$;

create or replace function public.is_super_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select public.current_user_role() = 'SUPER_ADMIN'
$$;

revoke all on function public.is_admin() from public, anon, authenticated;
grant execute on function public.is_admin() to anon, authenticated, service_role;

revoke all on function public.is_super_admin() from public, anon, authenticated;
grant execute on function public.is_super_admin() to anon, authenticated, service_role;

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
  if v_booking.id is null then
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

  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (v_user, 'reject_payment_proof', 'payment_proofs', v_proof.id,
          jsonb_build_object('booking_id', v_proof.booking_id, 'reason_code', p_reason_code));
end $$;

revoke all on function public.approve_payment_proof(bigint, text) from public, anon, authenticated;
grant execute on function public.approve_payment_proof(bigint, text) to authenticated, service_role;

revoke all on function public.reject_payment_proof(bigint, text) from public, anon, authenticated;
grant execute on function public.reject_payment_proof(bigint, text) to authenticated, service_role;
