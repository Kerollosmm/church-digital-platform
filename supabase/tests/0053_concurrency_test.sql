\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS pgtap;

-- dblink must not live in public: Supabase default privileges there grant EXECUTE to
-- anon and authenticated, letting any API caller open a postgres connection and bypass
-- RLS. Only supabase_admin can revoke those grants, so relocate the extension to an
-- unexposed schema, where it is created with no role grants at all.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
    WHERE e.extname = 'dblink' AND n.nspname = 'public'
  ) THEN
    DROP EXTENSION dblink;
  END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS dblink_test;
REVOKE ALL ON SCHEMA dblink_test FROM PUBLIC;
CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA dblink_test;

SET search_path = public, extensions, dblink_test;

BEGIN;

SELECT no_plan();

-- ==============================================================================
-- 0053_concurrency_test.sql
-- Concurrency regression tests for booking, payment/expiry, and outbox claim
-- ==============================================================================

-- Test 1: dblink security check - no execution granted to anon or authenticated
SELECT is(
  (SELECT count(*)::integer FROM pg_proc WHERE proname LIKE 'dblink%' AND proacl::text ~ '(anon|authenticated)'),
  0,
  'dblink functions must not be executable by anon or authenticated'
);

-- Test 2: Two concurrent book_slot calls on 1-capacity slot (T021a)
DO $$
DECLARE
  v_user1_id uuid := '00000000-0000-0000-0000-0000000000a1'::uuid;
  v_user2_id uuid := '00000000-0000-0000-0000-0000000000a2'::uuid;
  v_conn1 text := 'conn1';
  v_conn2 text := 'conn2';
  v_connstr text := 'dbname=postgres user=postgres password=postgres host=supabase_db_church port=5432';
  v_res text;
  v_success_count integer := 0;
  v_slot_full_count integer := 0;
BEGIN
  -- Open two connections
  PERFORM dblink_connect(v_conn1, v_connstr);
  PERFORM dblink_connect(v_conn2, v_connstr);

  -- Setup fixture across sessions
  PERFORM dblink_exec(v_conn1, $setup$
    INSERT INTO public.services (id, tenant_id, title_ar) OVERRIDING SYSTEM VALUE VALUES (991, 1, 'خدمة التزامن')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.service_slots (id, tenant_id, service_id, starts_at, ends_at, capacity, price, status) OVERRIDING SYSTEM VALUE
    VALUES (991, 1, 991, now() + interval '1 day', now() + interval '1 day 2 hours', 1, 1000, 'OPEN')
    ON CONFLICT (id) DO UPDATE SET capacity = 1, status = 'OPEN', starts_at = now() + interval '1 day';

    DELETE FROM public.payments WHERE booking_id IN (SELECT id FROM public.bookings WHERE slot_id = 991);
    DELETE FROM public.bookings WHERE slot_id = 991;

    INSERT INTO auth.users (id, instance_id, aud, role, email, phone, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES
      ('00000000-0000-0000-0000-0000000000a1'::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u1@test.local', '+201011111111', crypt('pw', gen_salt('bf')), now(), '{"provider":"email"}', '{}', now(), now()),
      ('00000000-0000-0000-0000-0000000000a2'::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u2@test.local', '+201022222222', crypt('pw', gen_salt('bf')), now(), '{"provider":"email"}', '{}', now(), now())
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (id, tenant_id, phone, name, role)
    VALUES
      ('00000000-0000-0000-0000-0000000000a1'::uuid, 1, '+201011111111', 'User 1', 'USER'),
      ('00000000-0000-0000-0000-0000000000a2'::uuid, 1, '+201022222222', 'User 2', 'USER')
    ON CONFLICT (id) DO NOTHING;
  $setup$);

  -- Session 1 setup claims
  PERFORM dblink_exec(v_conn1, format('SET request.jwt.claims = ''{"sub":"%s","role":"authenticated"}''', v_user1_id));

  -- Session 2 setup claims
  PERFORM dblink_exec(v_conn2, format('SET request.jwt.claims = ''{"sub":"%s","role":"authenticated"}''', v_user2_id));

  -- Send racing queries
  PERFORM dblink_send_query(v_conn1, 'SELECT (public.book_slot(991, false, NULL)).id::text');
  PERFORM dblink_send_query(v_conn2, 'SELECT (public.book_slot(991, false, NULL)).id::text');

  -- Collect result 1
  BEGIN
    SELECT res INTO v_res FROM dblink_get_result(v_conn1) AS t(res text);
    WHILE dblink_is_busy(v_conn1) = 1 LOOP NULL; END LOOP;
    PERFORM dblink_get_result(v_conn1); -- consume null end of result
    IF v_res IS NOT NULL THEN v_success_count := v_success_count + 1; END IF;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%SLOT_FULL%' THEN v_slot_full_count := v_slot_full_count + 1; END IF;
  END;

  -- Collect result 2
  BEGIN
    SELECT res INTO v_res FROM dblink_get_result(v_conn2) AS t(res text);
    WHILE dblink_is_busy(v_conn2) = 1 LOOP NULL; END LOOP;
    PERFORM dblink_get_result(v_conn2); -- consume null end of result
    IF v_res IS NOT NULL THEN v_success_count := v_success_count + 1; END IF;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%SLOT_FULL%' THEN v_slot_full_count := v_slot_full_count + 1; END IF;
  END;

  -- Teardown Test 2 fixture
  PERFORM dblink_exec(v_conn1, $cleanup$
    DELETE FROM public.payments WHERE booking_id IN (SELECT id FROM public.bookings WHERE slot_id = 991);
    DELETE FROM public.bookings WHERE slot_id = 991;
    DELETE FROM public.service_slots WHERE id = 991;
    DELETE FROM public.services WHERE id = 991;
    DELETE FROM public.users WHERE id IN ('00000000-0000-0000-0000-0000000000a1'::uuid, '00000000-0000-0000-0000-0000000000a2'::uuid);
    DELETE FROM auth.users WHERE id IN ('00000000-0000-0000-0000-0000000000a1'::uuid, '00000000-0000-0000-0000-0000000000a2'::uuid);
  $cleanup$);
  PERFORM dblink_disconnect(v_conn1);
  PERFORM dblink_disconnect(v_conn2);

  PERFORM is(v_success_count, 1, 'racing book_slot: exactly one succeeds');
  PERFORM is(v_slot_full_count, 1, 'racing book_slot: exactly one gets SLOT_FULL');
  RAISE NOTICE 'TEST2: success=%, slot_full=%', v_success_count, v_slot_full_count;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    PERFORM dblink_exec(v_conn1, $cleanup$
      DELETE FROM public.payments WHERE booking_id IN (SELECT id FROM public.bookings WHERE slot_id = 991);
      DELETE FROM public.bookings WHERE slot_id = 991;
      DELETE FROM public.service_slots WHERE id = 991;
      DELETE FROM public.services WHERE id = 991;
      DELETE FROM public.users WHERE id IN ('00000000-0000-0000-0000-0000000000a1'::uuid, '00000000-0000-0000-0000-0000000000a2'::uuid);
      DELETE FROM auth.users WHERE id IN ('00000000-0000-0000-0000-0000000000a1'::uuid, '00000000-0000-0000-0000-0000000000a2'::uuid);
    $cleanup$);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM dblink_disconnect(v_conn1); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM dblink_disconnect(v_conn2); EXCEPTION WHEN OTHERS THEN NULL; END;
  RAISE;
END $$;

-- Test 2b: Emit SLOT_EXHAUSTED realtime notification on book_slot taking last seat (T022)
DO $$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-0000000000a4'::uuid;
  v_conn_listen text := 'c_listen';
  v_conn_book text := 'c_book';
  v_connstr text := 'dbname=postgres user=postgres password=postgres host=supabase_db_church port=5432';
  v_notify_name text;
  v_be_pid int;
  v_extra text;
  v_payload jsonb;
BEGIN
  PERFORM dblink_connect(v_conn_listen, v_connstr);
  PERFORM dblink_connect(v_conn_book, v_connstr);

  -- Session 1: LISTEN on realtime channel
  PERFORM dblink_exec(v_conn_listen, 'LISTEN "realtime:event_inventory";');

  -- Setup fixture for 1-capacity slot
  PERFORM dblink_exec(v_conn_book, $setup$
    INSERT INTO public.services (id, tenant_id, title_ar) OVERRIDING SYSTEM VALUE VALUES (994, 1, 'خدمة الإشعار')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.service_slots (id, tenant_id, service_id, starts_at, ends_at, capacity, price, status) OVERRIDING SYSTEM VALUE
    VALUES (994, 1, 994, now() + interval '1 day', now() + interval '1 day 2 hours', 1, 0, 'OPEN')
    ON CONFLICT (id) DO UPDATE SET capacity = 1, status = 'OPEN', starts_at = now() + interval '1 day';

    DELETE FROM public.payments WHERE booking_id IN (SELECT id FROM public.bookings WHERE slot_id = 994);
    DELETE FROM public.bookings WHERE slot_id = 994;

    INSERT INTO auth.users (id, instance_id, aud, role, email, phone, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-0000000000a4'::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u4@test.local', '+201044444444', crypt('pw', gen_salt('bf')), now(), '{"provider":"email"}', '{}', now(), now())
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (id, tenant_id, phone, name, role)
    VALUES ('00000000-0000-0000-0000-0000000000a4'::uuid, 1, '+201044444444', 'User 4', 'USER')
    ON CONFLICT (id) DO NOTHING;
  $setup$);

  -- Session 2: Book slot as user (taking the only seat)
  PERFORM dblink_exec(v_conn_book, format('SET request.jwt.claims = ''{"sub":"%s","role":"authenticated"}''', v_user_id));
  PERFORM dblink_exec(v_conn_book, 'DO $b$ BEGIN PERFORM public.book_slot(994, false, NULL); END $b$;');

  -- Session 1: Check notification received. dblink_get_notify only reports what libpq
  -- has already consumed, so poll briefly instead of assuming instant delivery.
  FOR i IN 1..50 LOOP
    SELECT n.notify_name, n.be_pid, n.extra INTO v_notify_name, v_be_pid, v_extra
    FROM dblink_get_notify(v_conn_listen) AS n
    LIMIT 1;
    EXIT WHEN v_notify_name IS NOT NULL;
    PERFORM pg_sleep(0.1);
  END LOOP;

  v_payload := v_extra::jsonb;
  PERFORM is(v_notify_name, 'realtime:event_inventory', 'notification channel matches realtime:event_inventory');
  PERFORM is(v_payload ->> 'event', 'SLOT_EXHAUSTED', 'notification event is SLOT_EXHAUSTED');
  PERFORM is((v_payload -> 'payload' ->> 'slot_id')::bigint, 994::bigint, 'notification payload slot_id is 994');

  -- Teardown
  PERFORM dblink_exec(v_conn_book, $cleanup$
    DELETE FROM public.payments WHERE booking_id IN (SELECT id FROM public.bookings WHERE slot_id = 994);
    DELETE FROM public.bookings WHERE slot_id = 994;
    DELETE FROM public.service_slots WHERE id = 994;
    DELETE FROM public.services WHERE id = 994;
    DELETE FROM public.users WHERE id = '00000000-0000-0000-0000-0000000000a4'::uuid;
    DELETE FROM auth.users WHERE id = '00000000-0000-0000-0000-0000000000a4'::uuid;
  $cleanup$);

  PERFORM dblink_disconnect(v_conn_listen);
  PERFORM dblink_disconnect(v_conn_book);
EXCEPTION WHEN OTHERS THEN
  BEGIN
    PERFORM dblink_exec(v_conn_book, $cleanup$
      DELETE FROM public.payments WHERE booking_id IN (SELECT id FROM public.bookings WHERE slot_id = 994);
      DELETE FROM public.bookings WHERE slot_id = 994;
      DELETE FROM public.service_slots WHERE id = 994;
      DELETE FROM public.services WHERE id = 994;
      DELETE FROM public.users WHERE id = '00000000-0000-0000-0000-0000000000a4'::uuid;
      DELETE FROM auth.users WHERE id = '00000000-0000-0000-0000-0000000000a4'::uuid;
    $cleanup$);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM dblink_disconnect(v_conn_listen); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM dblink_disconnect(v_conn_book); EXCEPTION WHEN OTHERS THEN NULL; END;
  RAISE;
END $$;

-- Test 3: apply_payment racing expire_stale_bookings (T021b)
DO $$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-0000000000a3'::uuid;
  v_conn1 text := 'c_pay';
  v_conn2 text := 'c_exp';
  v_connstr text := 'dbname=postgres user=postgres password=postgres host=supabase_db_church port=5432';
  v_final_status text;
  v_status_locked text;
  v_status_after_pay text;
  v_pay_status text;
  v_expired_count integer;
  v_expired_count2 integer;
BEGIN
  PERFORM dblink_connect(v_conn1, v_connstr);
  PERFORM dblink_connect(v_conn2, v_connstr);

  -- Setup booking and payment in committed db state with stale locked_until
  PERFORM dblink_exec(v_conn1, $setup$
    INSERT INTO public.services (id, tenant_id, title_ar) OVERRIDING SYSTEM VALUE VALUES (993, 1, 'خدمة الدفع المتزامن')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.service_slots (id, tenant_id, service_id, starts_at, ends_at, capacity, price, status) OVERRIDING SYSTEM VALUE
    VALUES (993, 1, 993, now() + interval '1 day', now() + interval '1 day 2 hours', 1, 1000, 'OPEN')
    ON CONFLICT (id) DO UPDATE SET capacity = 1, status = 'OPEN', starts_at = now() + interval '1 day';

    INSERT INTO auth.users (id, instance_id, aud, role, email, phone, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-0000000000a3'::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u3@test.local', '+201033333333', crypt('pw', gen_salt('bf')), now(), '{"provider":"email"}', '{}', now(), now())
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (id, tenant_id, phone, name, role)
    VALUES ('00000000-0000-0000-0000-0000000000a3'::uuid, 1, '+201033333333', 'User 3', 'USER')
    ON CONFLICT (id) DO NOTHING;

    DELETE FROM public.payments WHERE booking_id IN (SELECT id FROM public.bookings WHERE slot_id = 993);
    DELETE FROM public.payments WHERE id = 99993;
    DELETE FROM public.bookings WHERE id = 99993 OR slot_id = 993;

    INSERT INTO public.bookings (id, tenant_id, slot_id, user_id, status, paid_amount, locked_until) OVERRIDING SYSTEM VALUE
    VALUES (99993, 1, 993, '00000000-0000-0000-0000-0000000000a3'::uuid, 'PENDING_PAYMENT', 0, now() - interval '1 minute');

    INSERT INTO public.payments (id, tenant_id, booking_id, amount, status) OVERRIDING SYSTEM VALUE
    VALUES (99993, 1, 99993, 1000, 'CREATED');
  $setup$);

  -- Step 2: Session 1 begins transaction and locks booking row 99993.
  -- dblink_exec rejects statements that return rows, so both the lock and the payment
  -- call are wrapped in DO blocks.
  PERFORM dblink_exec(v_conn1, 'BEGIN;');
  PERFORM dblink_exec(v_conn1, 'DO $b$ BEGIN PERFORM id FROM public.bookings WHERE id = 99993 FOR UPDATE; END $b$;');

  -- Step 3: Session 2 runs expire_stale_bookings() (must skip row 99993 due to FOR UPDATE SKIP LOCKED)
  SELECT res::integer INTO v_expired_count
  FROM dblink(v_conn2, 'SELECT public.expire_stale_bookings();') AS t(res integer);

  PERFORM is(v_expired_count, 0, 'expire_stale_bookings skips row locked by payment session');

  SELECT res INTO v_status_locked FROM dblink(v_conn2, 'SELECT status FROM public.bookings WHERE id = 99993') AS t(res text);

  -- Step 4: Session 1 applies payment on the expired lock and commits. apply_payment
  -- refuses to settle once locked_until has passed, so the money is parked for refund
  -- instead of the booking being confirmed.
  PERFORM dblink_exec(v_conn1, 'DO $b$ BEGIN PERFORM public.apply_payment(99993); END $b$;');
  PERFORM dblink_exec(v_conn1, 'COMMIT;');

  SELECT res INTO v_status_after_pay FROM dblink(v_conn2, 'SELECT status FROM public.bookings WHERE id = 99993') AS t(res text);
  SELECT res INTO v_pay_status FROM dblink(v_conn2, 'SELECT status::text FROM public.payments WHERE id = 99993') AS t(res text);

  -- Step 5: lock released, so the same row must now actually be reaped. Without this the
  -- zero in step 3 would prove nothing about SKIP LOCKED.
  SELECT res::integer INTO v_expired_count2
  FROM dblink(v_conn2, 'SELECT public.expire_stale_bookings();') AS t(res integer);

  SELECT res INTO v_final_status FROM dblink(v_conn2, 'SELECT status FROM public.bookings WHERE id = 99993') AS t(res text);

  -- Teardown
  PERFORM dblink_exec(v_conn1, $cleanup$
    DELETE FROM public.payments WHERE id = 99993;
    DELETE FROM public.bookings WHERE id = 99993;
    DELETE FROM public.service_slots WHERE id = 993;
    DELETE FROM public.services WHERE id = 993;
    DELETE FROM public.users WHERE id = '00000000-0000-0000-0000-0000000000a3'::uuid;
    DELETE FROM auth.users WHERE id = '00000000-0000-0000-0000-0000000000a3'::uuid;
  $cleanup$);
  PERFORM dblink_disconnect(v_conn1);
  PERFORM dblink_disconnect(v_conn2);

  PERFORM is(v_status_locked, 'PENDING_PAYMENT', 'locked booking is not cancelled by a concurrent expire_stale_bookings');
  PERFORM is(v_status_after_pay, 'PENDING_PAYMENT', 'apply_payment must not confirm a booking whose lock already expired');
  PERFORM is(v_pay_status, 'REFUND_PENDING', 'payment against an expired lock is parked for refund');
  PERFORM ok(v_expired_count2 >= 1, 'same row is reaped once the lock is released, proving it was a real expiry candidate');
  PERFORM is(v_final_status, 'CANCELLED', 'expired booking ends CANCELLED after the lock holder commits');
  RAISE NOTICE 'TEST3: locked=%, after_pay=%, pay=%, reaped2=%, final=%', v_status_locked, v_status_after_pay, v_pay_status, v_expired_count2, v_final_status;
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM dblink_exec(v_conn1, 'ROLLBACK;'); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    PERFORM dblink_exec(v_conn1, $cleanup$
      DELETE FROM public.payments WHERE id = 99993;
      DELETE FROM public.bookings WHERE id = 99993;
      DELETE FROM public.service_slots WHERE id = 993;
      DELETE FROM public.services WHERE id = 993;
      DELETE FROM public.users WHERE id = '00000000-0000-0000-0000-0000000000a3'::uuid;
      DELETE FROM auth.users WHERE id = '00000000-0000-0000-0000-0000000000a3'::uuid;
    $cleanup$);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM dblink_disconnect(v_conn1); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM dblink_disconnect(v_conn2); EXCEPTION WHEN OTHERS THEN NULL; END;
  RAISE;
END $$;

-- Test 4: Concurrent claim_event_outbox_batch never returns same row twice (T042)
DO $$
DECLARE
  v_conn1 text := 'out1';
  v_conn2 text := 'out2';
  v_connstr text := 'dbname=postgres user=postgres password=postgres host=supabase_db_church port=5432';
  v_overlap integer;
BEGIN
  PERFORM dblink_connect(v_conn1, v_connstr);
  PERFORM dblink_connect(v_conn2, v_connstr);

  -- Insert test outbox events
  PERFORM dblink_exec(v_conn1, $setup$
    INSERT INTO public.event_outbox (id, tenant_id, handler_type, payload, status) OVERRIDING SYSTEM VALUE
    VALUES
      (99991, 1, 'WHATSAPP', '{"template_name":"booking_confirmed","phone":"+201000000001"}'::jsonb, 'PENDING'),
      (99992, 1, 'WHATSAPP', '{"template_name":"booking_confirmed","phone":"+201000000002"}'::jsonb, 'PENDING'),
      (99993, 1, 'WHATSAPP', '{"template_name":"booking_confirmed","phone":"+201000000003"}'::jsonb, 'PENDING')
    ON CONFLICT (id) DO UPDATE SET status = 'PENDING';
  $setup$);

  PERFORM dblink_exec(v_conn1, 'BEGIN;');
  PERFORM dblink_exec(v_conn2, 'BEGIN;');

  -- Two workers claiming batch of 2
  SELECT count(*)::integer INTO v_overlap
  FROM (
    SELECT id FROM dblink(v_conn1, 'SELECT id FROM public.claim_event_outbox_batch(2)') AS t1(id bigint)
    INTERSECT
    SELECT id FROM dblink(v_conn2, 'SELECT id FROM public.claim_event_outbox_batch(2)') AS t2(id bigint)
  ) sub;

  PERFORM dblink_exec(v_conn1, 'COMMIT;');
  PERFORM dblink_exec(v_conn2, 'COMMIT;');

  -- Cleanup
  PERFORM dblink_exec(v_conn1, 'DELETE FROM public.event_outbox WHERE id IN (99991, 99992, 99993);');
  PERFORM dblink_disconnect(v_conn1);
  PERFORM dblink_disconnect(v_conn2);

  PERFORM is(v_overlap, 0, 'concurrent claim_event_outbox_batch must never overlap');
  RAISE NOTICE 'TEST4: overlap=%', v_overlap;
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM dblink_exec(v_conn1, 'ROLLBACK;'); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM dblink_exec(v_conn2, 'ROLLBACK;'); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM dblink_exec(v_conn1, 'DELETE FROM public.event_outbox WHERE id IN (99991, 99992, 99993);'); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM dblink_disconnect(v_conn1); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM dblink_disconnect(v_conn2); EXCEPTION WHEN OTHERS THEN NULL; END;
  RAISE;
END $$;

SELECT * FROM finish();
ROLLBACK;
