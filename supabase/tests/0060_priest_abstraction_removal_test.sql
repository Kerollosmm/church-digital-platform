\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;

SELECT plan(6);

-- 1. is_admin_or_priest function does not exist
SELECT is(
  (SELECT count(*)::integer FROM pg_proc WHERE proname = 'is_admin_or_priest'),
  0,
  'function public.is_admin_or_priest() must be dropped'
);

-- 2. No policies reference is_admin_or_priest
SELECT is(
  (SELECT count(*)::integer FROM pg_policies WHERE qual LIKE '%is_admin_or_priest%' OR with_check LIKE '%is_admin_or_priest%'),
  0,
  'no policies reference dropped is_admin_or_priest'
);

-- 3. No functions reference is_admin_or_priest
SELECT is(
  (SELECT count(*)::integer FROM pg_proc WHERE prosrc LIKE '%is_admin_or_priest%'),
  0,
  'no function definitions reference dropped is_admin_or_priest'
);

-- 4. Positive and negative write access on policies rewritten for is_admin()
DO $$
DECLARE
  v_admin_id uuid := '00000000-0000-0000-0000-000000000099'::uuid;
  v_user_id uuid := '00000000-0000-0000-0000-000000000088'::uuid;
  v_faq_id bigint;
  v_denied boolean := false;
BEGIN
  -- Setup test users
  INSERT INTO auth.users (id, instance_id, aud, role, email, phone, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES
    (v_admin_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin60@test.local', '+201099999960', crypt('pw', gen_salt('bf')), now(), '{"provider":"email"}', '{}', now(), now()),
    (v_user_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'user60@test.local', '+201088888860', crypt('pw', gen_salt('bf')), now(), '{"provider":"email"}', '{}', now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.users (id, tenant_id, phone, name, role)
  VALUES
    (v_admin_id, 1, '+201099999960', 'Admin 60', 'ADMIN'),
    (v_user_id, 1, '+201088888860', 'User 60', 'USER')
  ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role;

  -- Test Admin Write
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);

  INSERT INTO public.faq (question_ar, answer_ar, position, tenant_id)
  VALUES ('سؤال تجريبي', 'إجابة تجريبية', 99, 1)
  RETURNING id INTO v_faq_id;

  PERFORM ok(v_faq_id IS NOT NULL, 'admin can INSERT into faq table under is_admin policy');

  RESET ROLE;

  -- Test Non-Admin Write Denied
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_id::text, 'role', 'authenticated')::text, true);

  BEGIN
    INSERT INTO public.faq (question_ar, answer_ar, position, tenant_id)
    VALUES ('سؤال غير مصرح', 'إجابة', 100, 1);
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    v_denied := true;
  END;

  PERFORM ok(v_denied, 'non-admin cannot INSERT into faq table under is_admin policy');

  -- Test publish_announcement by non-admin denied with 42501
  BEGIN
    PERFORM public.publish_announcement(1);
    v_denied := false;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FORBIDDEN%' OR SQLSTATE = '42501' THEN
      v_denied := true;
    END IF;
  END;

  PERFORM ok(v_denied, 'non-admin EXECUTE on publish_announcement denied with FORBIDDEN (42501)');

  RESET ROLE;
END $$;

SELECT * FROM finish();

ROLLBACK;
