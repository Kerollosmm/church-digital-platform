-- 0067_submit_payment_proof.sql
-- 011 US1: member submits a manual payment proof on their own
-- PENDING_PAYMENT booking. Snapshot via existing create_pending_payment;
-- nothing financial moves until staff approval (0068).

create or replace function public.submit_payment_proof(
  p_booking_id bigint,
  p_channel public.payment_channel,
  p_sender_phone text,
  p_reference text,
  p_amount int,
  p_image_path text
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_booking public.bookings;
  v_proof_id bigint;
  v_payment_id bigint;
begin
  if v_user is null then
    raise exception 'UNAUTHORIZED' using errcode = '28000';
  end if;

  if p_sender_phone is null or btrim(p_sender_phone) = ''
     or p_reference is null or btrim(p_reference) = ''
     or p_amount is null or p_amount <= 0 then
    raise exception 'BAD_REQUEST';
  end if;

  select * into v_booking from public.bookings
    where id = p_booking_id and tenant_id = public.tenant_id();
  if v_booking.id is null then
    raise exception 'BAD_REQUEST';
  end if;

  if v_booking.user_id <> v_user then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if v_booking.status <> 'PENDING_PAYMENT' then
    raise exception 'BAD_REQUEST';
  end if;

  if p_channel = 'CASH' then
    if p_image_path is not null then
      raise exception 'BAD_REQUEST';
    end if;
  else
    if p_image_path is null then
      raise exception 'BAD_REQUEST';
    end if;
  end if;

  if exists (
    select 1 from public.payment_proofs
    where booking_id = p_booking_id and status = 'PENDING' and deleted_at is null
  ) then
    raise exception 'BAD_REQUEST';
  end if;

  if p_channel <> 'CASH' then
    if p_image_path not like public.tenant_id()::text || '/' || p_booking_id::text || '/%' then
      raise exception 'BAD_REQUEST';
    end if;
    if not exists (
      select 1 from storage.objects
      where bucket_id = 'payment-proofs' and name = p_image_path
    ) then
      raise exception 'BAD_REQUEST';
    end if;
  end if;

  v_payment_id := public.create_pending_payment(p_booking_id, p_amount::numeric, null);

  insert into public.payment_proofs
    (booking_id, payment_id, channel, sender_phone, reference_number,
     amount_claimed, image_path, status)
  values
    (p_booking_id, v_payment_id, p_channel, p_sender_phone, p_reference,
     p_amount, p_image_path, 'PENDING')
  returning id into v_proof_id;

  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (v_user, 'submit_payment_proof', 'payment_proofs', v_proof_id,
          jsonb_build_object('booking_id', p_booking_id, 'channel', p_channel,
                             'payment_id', v_payment_id, 'amount_claimed', p_amount));

  return v_proof_id;
end $$;

revoke all on function public.submit_payment_proof(bigint, public.payment_channel, text, text, int, text)
  from public, anon, authenticated;
grant execute on function public.submit_payment_proof(bigint, public.payment_channel, text, text, int, text)
  to authenticated;
