-- 0069_mark_cash_received.sql
-- 011 US3: Staff-only mark_cash_received RPC
-- Atomically creates an APPROVED CASH proof, creates a pending payment snapshot,
-- and delegates to apply_payment within a single database transaction.

CREATE OR REPLACE FUNCTION public.create_pending_payment(
  p_booking_id bigint,
  p_amount numeric,
  p_gateway_ref text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_is_service boolean := coalesce(auth.role(), '') = 'service_role' or current_user = 'service_role';
  v_booking public.bookings;
  v_pay_id bigint;
  v_ref text;
BEGIN
  IF v_user_id IS NULL AND NOT v_is_service THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_booking FROM public.bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_booking IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF NOT v_is_service AND NOT public.is_admin() AND v_booking.user_id <> v_user_id THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF v_booking.status <> 'PENDING_PAYMENT' THEN
    RAISE EXCEPTION 'INVALID_STATUS: booking is not pending payment' USING ERRCODE = 'P0001';
  END IF;

  v_ref := COALESCE(p_gateway_ref, 'pay_' || extract(epoch from clock_timestamp())::bigint || '_' || p_booking_id);

  INSERT INTO public.payments (
    booking_id, amount, status, gateway_ref, tenant_id
  ) VALUES (
    p_booking_id, COALESCE(p_amount::int, 0), 'CREATED', v_ref, v_booking.tenant_id
  ) RETURNING id INTO v_pay_id;

  -- Maintain merchant_order_id stamping
  UPDATE public.payments SET merchant_order_id = v_pay_id::text WHERE id = v_pay_id;

  RETURN v_pay_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_pending_payment(bigint, numeric, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_pending_payment(bigint, numeric, text) TO authenticated, service_role;

create or replace function public.mark_cash_received(
  p_booking_id bigint,
  p_amount int,
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
  v_booking public.bookings;
  v_payment_id bigint;
  v_proof_id bigint;
  v_user_phone text;
begin
  if v_user is null then
    raise exception 'UNAUTHORIZED' using errcode = '28000';
  end if;

  select role into v_role from public.users where id = v_user;
  if v_role is null or v_role not in ('ADMIN', 'SUPER_ADMIN') then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'BAD_REQUEST';
  end if;

  select * into v_booking from public.bookings
    where id = p_booking_id and tenant_id = public.tenant_id()
    for update;
  if v_booking.id is null or v_booking.status <> 'PENDING_PAYMENT' then
    raise exception 'BAD_REQUEST';
  end if;

  if exists (
    select 1 from public.payment_proofs
    where booking_id = p_booking_id
      and status = 'PENDING'
      and tenant_id = public.tenant_id()
  ) then
    raise exception 'BAD_REQUEST';
  end if;

  select phone into v_user_phone from public.users where id = v_booking.user_id;

  v_payment_id := public.create_pending_payment(
    p_booking_id,
    p_amount,
    'cash_' || p_booking_id || '_' || extract(epoch from clock_timestamp())::bigint
  );

  insert into public.payment_proofs (
    booking_id,
    payment_id,
    channel,
    sender_phone,
    reference_number,
    amount_claimed,
    image_path,
    status,
    collector_note,
    reviewed_by,
    reviewed_at,
    tenant_id
  ) values (
    p_booking_id,
    v_payment_id,
    'CASH',
    coalesce(v_user_phone, ''),
    'CASH_' || p_booking_id || '_' || extract(epoch from clock_timestamp())::bigint,
    p_amount,
    null,
    'APPROVED',
    p_collector_note,
    v_user,
    now(),
    v_booking.tenant_id
  ) returning id into v_proof_id;

  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (v_user, 'mark_cash_received', 'payment_proofs', v_proof_id,
          jsonb_build_object('booking_id', p_booking_id, 'payment_id', v_payment_id,
                             'amount', p_amount, 'collector_note', p_collector_note));

  perform public.apply_payment(v_payment_id);

  return jsonb_build_object(
    'proof_id', v_proof_id,
    'booking_id', p_booking_id,
    'payment_id', v_payment_id
  );
end $$;

revoke all on function public.mark_cash_received(bigint, int, text) from public, anon, authenticated;
grant execute on function public.mark_cash_received(bigint, int, text) to authenticated, service_role;
