\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;

SELECT no_plan();

-- ==============================================================================
-- 0053_security_fixes_test.sql
-- pgTAP regression suite for 007-backend-security-fixes
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- US1 Tests: Direct DML refusal on payments, complaints, audit_log, roles_permissions, users
-- ------------------------------------------------------------------------------

DO $$
DECLARE
  v_denied boolean;
BEGIN
  -- 1. anon DML refusal
  SET LOCAL ROLE anon;
  PERFORM set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000000","role":"anon"}', true);

  -- payments
  BEGIN
    INSERT INTO public.payments(tenant_id, amount, status) VALUES (1, 100, 'CREATED');
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon INSERT on payments denied with 42501');

  BEGIN
    UPDATE public.payments SET status = 'PAID' WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon UPDATE on payments denied with 42501');

  BEGIN
    DELETE FROM public.payments WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon DELETE on payments denied with 42501');

  -- complaints
  BEGIN
    INSERT INTO public.complaints(tenant_id, user_id, category, body_encrypted) VALUES (1, '00000000-0000-0000-0000-000000000000'::uuid, 'General', 'test'::bytea);
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon INSERT on complaints denied with 42501');

  BEGIN
    UPDATE public.complaints SET status = 'RESOLVED' WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon UPDATE on complaints denied with 42501');

  BEGIN
    DELETE FROM public.complaints WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon DELETE on complaints denied with 42501');

  -- audit_log
  BEGIN
    INSERT INTO public.audit_log(action, entity_type) VALUES ('TEST', 'payments');
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon INSERT on audit_log denied with 42501');

  BEGIN
    UPDATE public.audit_log SET action = 'HACK' WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon UPDATE on audit_log denied with 42501');

  BEGIN
    DELETE FROM public.audit_log WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon DELETE on audit_log denied with 42501');

  -- roles_permissions
  BEGIN
    INSERT INTO public.roles_permissions(role, resource, action) VALUES ('ADMIN', 'test', 'READ');
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon INSERT on roles_permissions denied with 42501');

  BEGIN
    UPDATE public.roles_permissions SET action = 'UPDATE' WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon UPDATE on roles_permissions denied with 42501');

  BEGIN
    DELETE FROM public.roles_permissions WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon DELETE on roles_permissions denied with 42501');

  -- users
  BEGIN
    INSERT INTO public.users(id, tenant_id, phone, name, role) VALUES (gen_random_uuid(), 1, '+201000000001', 'Test', 'USER');
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon INSERT on users denied with 42501');

  BEGIN
    UPDATE public.users SET role = 'ADMIN' WHERE phone = '+201000000001';
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon UPDATE on users denied with 42501');

  BEGIN
    DELETE FROM public.users WHERE phone = '+201000000001';
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon DELETE on users denied with 42501');

  -- US1 RPC checks for anon
  BEGIN
    PERFORM public.apply_payment(1);
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon EXECUTE on apply_payment denied with 42501');

  BEGIN
    PERFORM public.rbac_allows('ADMIN'::public.app_role, 'payments', 'update');
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'anon EXECUTE on rbac_allows denied with 42501');

  RESET ROLE;

  -- 2. authenticated DML refusal
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000053","role":"authenticated"}', true);

  -- payments
  BEGIN
    INSERT INTO public.payments(tenant_id, amount, status) VALUES (1, 100, 'CREATED');
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated INSERT on payments denied with 42501');

  BEGIN
    UPDATE public.payments SET status = 'PAID' WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated UPDATE on payments denied with 42501');

  BEGIN
    DELETE FROM public.payments WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated DELETE on payments denied with 42501');

  -- complaints
  BEGIN
    INSERT INTO public.complaints(tenant_id, user_id, category, body_encrypted) VALUES (1, '00000000-0000-0000-0000-000000000053'::uuid, 'General', 'test'::bytea);
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated INSERT on complaints denied with 42501');

  BEGIN
    UPDATE public.complaints SET status = 'RESOLVED' WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated UPDATE on complaints denied with 42501');

  BEGIN
    DELETE FROM public.complaints WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated DELETE on complaints denied with 42501');

  -- audit_log
  BEGIN
    INSERT INTO public.audit_log(action, entity_type) VALUES ('TEST', 'payments');
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated INSERT on audit_log denied with 42501');

  BEGIN
    UPDATE public.audit_log SET action = 'HACK' WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated UPDATE on audit_log denied with 42501');

  BEGIN
    DELETE FROM public.audit_log WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated DELETE on audit_log denied with 42501');

  -- roles_permissions
  BEGIN
    INSERT INTO public.roles_permissions(role, resource, action) VALUES ('ADMIN', 'test', 'READ');
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated INSERT on roles_permissions denied with 42501');

  BEGIN
    UPDATE public.roles_permissions SET action = 'UPDATE' WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated UPDATE on roles_permissions denied with 42501');

  BEGIN
    DELETE FROM public.roles_permissions WHERE id = 1;
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated DELETE on roles_permissions denied with 42501');

  -- users
  BEGIN
    INSERT INTO public.users(id, tenant_id, phone, name, role) VALUES (gen_random_uuid(), 1, '+201000000002', 'Test2', 'USER');
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated INSERT on users denied with 42501');

  BEGIN
    UPDATE public.users SET role = 'ADMIN' WHERE phone = '+201000000002';
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated UPDATE on users denied with 42501');

  BEGIN
    DELETE FROM public.users WHERE phone = '+201000000002';
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated DELETE on users denied with 42501');

  -- US1 RPC checks for authenticated
  BEGIN
    PERFORM public.apply_payment(1);
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated EXECUTE on apply_payment denied with 42501');

  BEGIN
    PERFORM public.expire_stale_bookings();
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated EXECUTE on expire_stale_bookings denied with 42501');

  BEGIN
    PERFORM public.promote_waiting_list(1);
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated EXECUTE on promote_waiting_list denied with 42501');

  BEGIN
    PERFORM public.materialize_analytics();
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  PERFORM ok(v_denied, 'authenticated EXECUTE on materialize_analytics denied with 42501');

  RESET ROLE;
END $$;

-- ------------------------------------------------------------------------------
-- T010: Positive-read assertions for Admin
-- ------------------------------------------------------------------------------
DO $$
DECLARE
  v_admin_auth_id uuid := '00000000-0000-0000-0000-000000000099'::uuid;
  v_count bigint;
BEGIN
  -- Insert into auth.users first to satisfy FK if needed
  INSERT INTO auth.users (id, instance_id, aud, role, email, phone, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES (v_admin_auth_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin_test@test.local', '+201099999999', crypt('password', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now())
  ON CONFLICT (id) DO NOTHING;

  -- Ensure test admin user exists in public.users
  INSERT INTO public.users (id, tenant_id, phone, name, role)
  VALUES (v_admin_auth_id, 1, '+201099999999', 'Admin Test User', 'ADMIN')
  ON CONFLICT (id) DO UPDATE SET role = 'ADMIN';

  -- Seed a row in audit_log, roles_permissions, payments, and complaints if empty
  INSERT INTO public.audit_log (action, entity_type) VALUES ('TEST_SEED', 'test');
  INSERT INTO public.payments (tenant_id, amount, status)
  VALUES (1, 5000, 'CREATED');
  INSERT INTO public.complaints (tenant_id, user_id, category, body_encrypted)
  VALUES (1, v_admin_auth_id, 'General', 'test complaint'::bytea);

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_auth_id::text, 'role', 'authenticated')::text, true);

  -- Admin can SELECT from payments
  SELECT count(*) INTO v_count FROM public.payments;
  PERFORM ok(v_count >= 1, 'admin can SELECT from payments');

  -- Admin can SELECT from audit_log
  SELECT count(*) INTO v_count FROM public.audit_log;
  PERFORM ok(v_count >= 1, 'admin can SELECT from audit_log');

  -- Admin can SELECT from roles_permissions
  SELECT count(*) INTO v_count FROM public.roles_permissions;
  PERFORM ok(v_count >= 1, 'admin can SELECT from roles_permissions');

  -- Admin can SELECT from v_complaints
  SELECT count(*) INTO v_count FROM public.v_complaints;
  PERFORM ok(v_count >= 1, 'admin can SELECT from v_complaints');

  RESET ROLE;
END $$;

-- ------------------------------------------------------------------------------
-- US2 Tests: Accurate Slot Capacity Without Counter Drift
-- ------------------------------------------------------------------------------

-- T020: Pin v_available_slots column contract
SELECT columns_are(
  'public',
  'v_available_slots',
  ARRAY[
    'slot_id',
    'service_id',
    'title_ar',
    'starts_at',
    'ends_at',
    'capacity',
    'price',
    'location',
    'booked_count',
    'available_seats',
    'slot_status'
  ],
  'v_available_slots must preserve exact 11 columns in order'
);

-- T022: book_slot takes last seat on 1-capacity slot
DO $$
DECLARE
  v_user_auth_id uuid := '00000000-0000-0000-0000-000000000088'::uuid;
  v_booking public.bookings;
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email, phone, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES (v_user_auth_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u88@test.local', '+201088888888', crypt('pw', gen_salt('bf')), now(), '{"provider":"email"}', '{}', now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.users (id, tenant_id, phone, name, role)
  VALUES (v_user_auth_id, 1, '+201088888888', 'Test 88', 'USER')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.services (id, tenant_id, title_ar) OVERRIDING SYSTEM VALUE VALUES (988, 1, 'خدمة الحجز الأخير')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.service_slots (id, tenant_id, service_id, starts_at, ends_at, capacity, price, status) OVERRIDING SYSTEM VALUE
  VALUES (988, 1, 988, now() + interval '2 days', now() + interval '2 days 2 hours', 1, 0, 'OPEN')
  ON CONFLICT (id) DO UPDATE SET capacity = 1, status = 'OPEN';

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_auth_id::text, 'role', 'authenticated')::text, true);

  -- Perform book_slot on last seat
  v_booking := public.book_slot(988, false, NULL);
  PERFORM ok(v_booking.id IS NOT NULL, 'book_slot succeeded on 1-capacity slot');

  RESET ROLE;
END $$;

-- US2 Schema Checks: dropped remaining_capacity, triggers, helpers, overloads
SELECT is(
  (SELECT count(*)::integer FROM information_schema.columns WHERE table_name = 'service_slots' AND column_name = 'remaining_capacity'),
  0,
  'service_slots.remaining_capacity column must be dropped'
);

SELECT is(
  (SELECT count(*)::integer FROM pg_proc WHERE proname IN ('fn_restore_slot_capacity_on_cancel', 'fn_broadcast_slot_depletion', 'fn_book_slot_atomic')),
  0,
  'deprecated capacity functions must be dropped'
);

SELECT is(
  (SELECT count(*)::integer FROM pg_proc WHERE proname = 'book_slot'),
  1,
  'book_slot must have exactly 1 consolidated overload'
);

-- ------------------------------------------------------------------------------
-- US3 Tests: Decommissioning of Video Machinery
-- ------------------------------------------------------------------------------

-- T037: Absence assertions for video schema and functions
SELECT is(
  (SELECT count(*)::integer FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('videos', 'video_purchases')),
  0,
  'videos and video_purchases tables must be dropped'
);

SELECT is(
  (SELECT count(*)::integer FROM information_schema.columns WHERE table_name = 'payments' AND column_name = 'video_id'),
  0,
  'payments.video_id column must be dropped'
);

SELECT is(
  (SELECT count(*)::integer FROM pg_proc WHERE proname IN ('purchase_video', 'apply_video_payment', 'deliver_personal_video')),
  0,
  'video RPCs must be dropped'
);

-- ------------------------------------------------------------------------------
-- US4 Tests: Resilient Background Dispatch & Outbox Recovery
-- ------------------------------------------------------------------------------

-- T041: Outbox schema, reaper, admin resend RPC, v_failed_outbox_events
SELECT is(
  (SELECT count(*)::integer FROM information_schema.columns WHERE table_name = 'event_outbox' AND column_name IN ('claimed_at', 'last_error')),
  2,
  'event_outbox must have claimed_at and last_error columns'
);

DO $$
DECLARE
  v_admin_auth_id uuid := '00000000-0000-0000-0000-000000000099'::uuid;
  v_user_auth_id uuid := '00000000-0000-0000-0000-000000000088'::uuid;
  v_event1_id bigint;
  v_event2_id bigint;
  v_reaped integer;
  v_resend_res jsonb;
  v_count integer;
  v_denied boolean;
BEGIN
  -- 1. Insert outbox events stuck in PROCESSING
  INSERT INTO public.event_outbox (tenant_id, handler_type, payload, status, attempts, claimed_at)
  VALUES (1, 'WHATSAPP', '{"template_name":"booking_confirmed","phone":"+201000000001"}'::jsonb, 'PROCESSING', 2, now() - interval '10 minutes')
  RETURNING id INTO v_event1_id;

  INSERT INTO public.event_outbox (tenant_id, handler_type, payload, status, attempts, claimed_at)
  VALUES (1, 'WHATSAPP', '{"template_name":"booking_confirmed","phone":"+201000000002"}'::jsonb, 'PROCESSING', 5, now() - interval '10 minutes')
  RETURNING id INTO v_event2_id;

  -- 2. Run reaper
  v_reaped := public.reap_stuck_outbox_events(interval '5 minutes');
  PERFORM is(v_reaped, 2, 'reap_stuck_outbox_events must process 2 stuck events');

  -- Event 1 with attempts=2 should become PENDING with attempts=3
  PERFORM ok(
    EXISTS (SELECT 1 FROM public.event_outbox WHERE id = v_event1_id AND status = 'PENDING' AND attempts = 3 AND claimed_at IS NULL),
    'reaper increments attempts and resets status to PENDING for attempts < 5'
  );

  -- Event 2 with attempts=5 should become FAILED with last_error set
  PERFORM ok(
    EXISTS (SELECT 1 FROM public.event_outbox WHERE id = v_event2_id AND status = 'FAILED' AND attempts = 5 AND last_error IS NOT NULL),
    'reaper parks attempts=5 event as FAILED with last_error'
  );

  -- 3. Test admin_resend_outbox_event as Admin
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_auth_id::text, 'role', 'authenticated')::text, true);

  v_resend_res := public.admin_resend_outbox_event(v_event2_id);
  PERFORM is(v_resend_res ->> 'success', 'true', 'admin_resend_outbox_event returns success true');
  PERFORM is(v_resend_res ->> 'status', 'PENDING', 'admin_resend_outbox_event returns status PENDING');

  RESET ROLE;
  PERFORM ok(
    EXISTS (SELECT 1 FROM public.event_outbox WHERE id = v_event2_id AND status = 'PENDING' AND attempts = 0 AND last_error IS NULL AND claimed_at IS NULL),
    'admin_resend_outbox_event resets event to PENDING with attempts=0'
  );

  -- 3b. Test admin_resend_outbox_event with non-existent id as Admin (T041: must raise EVENT_NOT_FOUND / P0002)
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_auth_id::text, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.admin_resend_outbox_event(999999999);
    v_denied := false;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%EVENT_NOT_FOUND%' OR SQLSTATE = 'P0002' THEN v_denied := true; END IF;
  END;
  PERFORM ok(v_denied, 'admin_resend_outbox_event with non-existent id raises EVENT_NOT_FOUND (P0002)');
  RESET ROLE;

  -- 4. Test admin_resend_outbox_event as non-admin (must raise FORBIDDEN)
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_auth_id::text, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.admin_resend_outbox_event(v_event2_id);
    v_denied := false;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FORBIDDEN%' OR SQLSTATE = '42501' THEN v_denied := true; END IF;
  END;
  PERFORM ok(v_denied, 'admin_resend_outbox_event denied to non-admin');

  -- 5. v_failed_outbox_events view access: non-admin gets 0 rows
  SELECT count(*)::integer INTO v_count FROM public.v_failed_outbox_events;
  PERFORM is(v_count, 0, 'non-admin sees 0 rows from v_failed_outbox_events');

  -- 6. v_complaints is a definer-rights view (security_invoker=false) granted to
  -- authenticated, so the is_admin() predicate in its body is the only barrier
  -- between a normal user and every complaint row. Guard it in both directions.
  SELECT count(*)::integer INTO v_count FROM public.v_complaints;
  PERFORM is(v_count, 0, 'non-admin sees 0 rows from v_complaints');

  RESET ROLE;
END $$;

-- ------------------------------------------------------------------------------
-- US5 Tests: Explicit Administrative Roles & Hierarchy
-- ------------------------------------------------------------------------------

-- T054: Role assertions for SUPER_ADMIN vs ADMIN and no PRIEST
DO $$
DECLARE
  v_super_auth_id uuid := '00000000-0000-0000-0000-000000000077'::uuid;
  v_admin_auth_id uuid := '00000000-0000-0000-0000-000000000099'::uuid;
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email, phone, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES (v_super_auth_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'super@test.local', '+201077777777', crypt('pw', gen_salt('bf')), now(), '{"provider":"email"}', '{}', now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.users (id, tenant_id, phone, name, role)
  VALUES (v_super_auth_id, 1, '+201077777777', 'Super Admin User', 'SUPER_ADMIN')
  ON CONFLICT (id) DO UPDATE SET role = 'SUPER_ADMIN';

  -- Test as SUPER_ADMIN
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_super_auth_id::text, 'role', 'authenticated')::text, true);
  PERFORM is(public.is_super_admin(), true, 'is_super_admin() is true for SUPER_ADMIN role');

  -- Test as ADMIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_auth_id::text, 'role', 'authenticated')::text, true);
  PERFORM is(public.is_super_admin(), false, 'is_super_admin() is false for ADMIN role');

  RESET ROLE;

  -- Assert PRIEST is not present in app_role enum
  PERFORM ok(
    NOT EXISTS (
      SELECT 1 FROM pg_enum e
      JOIN pg_type t ON t.oid = e.enumtypid
      WHERE t.typname = 'app_role' AND e.enumlabel = 'PRIEST'
    ),
    'retired PRIEST role is not present in app_role enum'
  );

  -- Assert no roles_permissions reference PRIEST
  PERFORM is(
    (SELECT count(*)::integer FROM public.roles_permissions WHERE role::text = 'PRIEST'),
    0,
    'no roles_permissions entries reference retired PRIEST role'
  );

  -- Assert no users have PRIEST role
  PERFORM is(
    (SELECT count(*)::integer FROM public.users WHERE role::text = 'PRIEST'),
    0,
    'no users have retired PRIEST role'
  );
END $$;

SELECT * FROM finish();
ROLLBACK;

