-- 0063_service_role_grants_and_payment_rpc.sql
-- Grant missing DML to service_role on restricted tables and create record_booking_payment RPC

-- 1. Explicit grants for service_role on restricted tables
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payments TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.complaints TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.audit_log TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.roles_permissions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.users TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role, postgres;

-- 2. Drop stale book_slot overloads and grant canonical book_slot
DROP FUNCTION IF EXISTS public.book_slot(bigint);
DROP FUNCTION IF EXISTS public.book_slot(bigint, boolean);
GRANT EXECUTE ON FUNCTION public.book_slot(bigint, boolean, uuid) TO authenticated, service_role;

-- 3. Allow transition_booking_status to process apply_payment action
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
begin
  select * into v_book from public.bookings where id = p_booking_id for update;
  if v_book is null then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_book.status = p_new_status then return v_book; end if;

  -- SECURITY DEFINER must never widen access: re-assert gates here.
  if v_role not in ('ADMIN','PRIEST','SUPER_ADMIN') and v_book.user_id <> auth.uid() and p_action <> 'apply_payment'
  then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
  
  -- Regular users can only cancel their own bookings, or transition to AWAITING_CALL via apply_payment
  if v_role not in ('ADMIN','PRIEST','SUPER_ADMIN') then
    if p_new_status not in ('CANCELLED') and not (p_action = 'apply_payment' and p_new_status = 'AWAITING_CALL') then
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
          jsonb_build_object('old_status', v_old_status, 'new_status', p_new_status,
                             'reason', p_reason, 'slot_id', v_book.slot_id) || p_metadata);
  return v_book;
end $$;

-- 4. Atomic RPC for recording booking payments (User Online Payment & Admin Cash)
CREATE OR REPLACE FUNCTION public.record_booking_payment(
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
  v_role text := public.current_user_role();
  v_booking public.bookings;
  v_pay_id bigint;
  v_ref text;
  v_amount int;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_booking FROM public.bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_booking IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_role NOT IN ('ADMIN','SUPER_ADMIN','PRIEST') AND v_booking.user_id <> v_user_id THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF v_booking.status <> 'PENDING_PAYMENT' THEN
    RAISE EXCEPTION 'INVALID_STATUS: booking is not pending payment' USING ERRCODE = 'P0001';
  END IF;

  v_amount := COALESCE(p_amount::int, v_booking.paid_amount, 0);
  v_ref := COALESCE(p_gateway_ref, 'pay_' || extract(epoch from now())::bigint || '_' || p_booking_id);

  INSERT INTO public.payments (
    booking_id,
    amount,
    status,
    gateway_ref,
    merchant_order_id,
    tenant_id
  ) VALUES (
    p_booking_id,
    v_amount,
    'CREATED',
    v_ref,
    p_booking_id::text,
    v_booking.tenant_id
  ) RETURNING id INTO v_pay_id;

  PERFORM public.apply_payment(v_pay_id);

  RETURN v_pay_id;
END;
$$;

REVOKE ALL ON FUNCTION public.record_booking_payment(bigint, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_booking_payment(bigint, numeric, text) TO authenticated, service_role;
