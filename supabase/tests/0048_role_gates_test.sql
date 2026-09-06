\set ON_ERROR_STOP on
create schema if not exists tests;
create or replace function tests.expect(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if not p_cond then raise exception 'FAIL: %', p_msg; end if;
end $$;
grant usage on schema tests to anon, authenticated, service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;

BEGIN;

-- 0. Seed test users
INSERT INTO auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES 
  ('00000000-0000-0000-0000-000000000048', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'user48@test.local', '+201099990048', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000049', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin49@test.local', '+201099990049', '{}', '{}', now(), now())
ON CONFLICT (id) DO NOTHING;

UPDATE public.users SET role = 'USER', tenant_id = 1, deleted_at = null WHERE id = '00000000-0000-0000-0000-000000000048';
UPDATE public.users SET role = 'ADMIN', tenant_id = 1, deleted_at = null WHERE id = '00000000-0000-0000-0000-000000000049';

-- 1. Create a test slot
DO $$
DECLARE
  v_slot_id BIGINT;
  v_book public.bookings;
  v_cancelled public.bookings;
BEGIN
  INSERT INTO public.services (id, title_ar, tenant_id) OVERRIDING SYSTEM VALUE
  VALUES (99948, 'خدمة تجريبية 48', 1) ON CONFLICT DO NOTHING;

  INSERT INTO public.service_slots (id, service_id, starts_at, ends_at, capacity, price, status, tenant_id)
  OVERRIDING SYSTEM VALUE
  VALUES (99948, 99948, now() + interval '5 days', now() + interval '5 days 2 hours', 10, 0, 'OPEN', 1)
  ON CONFLICT (id) DO UPDATE SET status = 'OPEN', starts_at = now() + interval '5 days'
  RETURNING id INTO v_slot_id;

  -- 2. USER can book slot via book_slot
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000048', 'role', 'authenticated')::text, true);

  SELECT * INTO v_book FROM public.book_slot(99948, false);
  PERFORM tests.expect(v_book.id IS NOT NULL, 'USER should successfully book slot via book_slot');
  PERFORM tests.expect(v_book.status = 'PENDING_PAYMENT', 'Booking initial status should be PENDING_PAYMENT');

  -- 3. USER can cancel own booking via transition_booking_status
  SELECT * INTO v_cancelled FROM public.transition_booking_status(v_book.id, 'CANCELLED', 'cancel_self');
  PERFORM tests.expect(v_cancelled.status = 'CANCELLED', 'USER should be able to cancel own booking');

  -- 4. USER cannot transition booking to CONFIRMED directly (only CANCELLED allowed)
  BEGIN
    PERFORM public.transition_booking_status(v_book.id, 'CONFIRMED', 'illegal_confirm');
    RAISE EXCEPTION 'USER must NOT be allowed to transition booking to CONFIRMED';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%FORBIDDEN%' OR SQLSTATE = '42501' THEN
        NULL;
      ELSE
        RAISE;
      END IF;
  END;
END $$;

-- 5. Negative Authorization Tests: anon execution of book_slot denied
DO $$
BEGIN
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.book_slot(99948, false);
    RAISE EXCEPTION 'Negative authorization check failed: anon executed book_slot';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLSTATE IN ('42501', '28000') THEN NULL; ELSE RAISE; END IF;
  END;
END $$;

-- 6. Negative Authorization Tests: anon execution of transition_booking_status denied
DO $$
BEGIN
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.transition_booking_status(1::bigint, 'CANCELLED', 'test');
    RAISE EXCEPTION 'Negative authorization check failed: anon executed transition_booking_status';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLSTATE IN ('42501', '28000') THEN NULL; ELSE RAISE; END IF;
  END;
END $$;

ROLLBACK;
