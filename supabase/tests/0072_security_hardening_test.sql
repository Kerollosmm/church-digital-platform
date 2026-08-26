\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;

SELECT plan(6);

-- 1. video_purchases table does not exist in schema
SELECT is(
  (SELECT count(*)::integer FROM pg_tables WHERE schemaname = 'public' AND tablename = 'video_purchases'),
  0,
  'table public.video_purchases must not exist'
);

-- 2. publish_announcement definition uses format pattern matching
SELECT ok(
  (SELECT prosrc LIKE '%format(%' FROM pg_proc WHERE proname = 'publish_announcement'),
  'publish_announcement must use formatted pattern matching for storage objects'
);

-- 3. Anonymous role cannot execute publish_announcement
DO $$
DECLARE
  v_denied boolean := false;
BEGIN
  SET LOCAL ROLE anon;
  PERFORM set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000000","role":"anon"}', true);

  BEGIN
    PERFORM public.publish_announcement(1);
    v_denied := false;
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    v_denied := true;
  END;

  PERFORM ok(v_denied, 'anon must be denied execute on publish_announcement');

  RESET ROLE;
END $$;

-- 4. Positive and negative write access and execution tests
DO $$
DECLARE
  v_admin_id uuid := '00000000-0000-0000-0000-000000000072'::uuid;
  v_user_id uuid := '00000000-0000-0000-0000-000000000073'::uuid;
  v_ann_id bigint;
  v_denied boolean := false;
BEGIN
  -- Setup test users
  INSERT INTO auth.users (id, instance_id, aud, role, email, phone, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES
    (v_admin_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin72@test.local', '+201099999972', crypt('pw', gen_salt('bf')), now(), '{"provider":"email"}', '{}', now(), now()),
    (v_user_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'user72@test.local', '+201088888872', crypt('pw', gen_salt('bf')), now(), '{"provider":"email"}', '{}', now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.users (id, tenant_id, phone, name, role)
  VALUES
    (v_admin_id, 1, '+201099999972', 'Admin 72', 'ADMIN'),
    (v_user_id, 1, '+201088888872', 'User 72', 'USER')
  ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role;

  -- Create a test announcement without images
  INSERT INTO public.announcements (title_ar, body_ar, tenant_id)
  VALUES ('إعلان أمني', 'تفاصيل الإعلان بدون صور', 1)
  RETURNING id INTO v_ann_id;

  -- Test regular authenticated user denied
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_id::text, 'role', 'authenticated')::text, true);

  BEGIN
    PERFORM public.publish_announcement(v_ann_id);
    v_denied := false;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FORBIDDEN%' OR SQLSTATE = '42501' THEN
      v_denied := true;
    END IF;
  END;

  PERFORM ok(v_denied, 'regular user cannot execute publish_announcement');

  RESET ROLE;

  -- Test admin can successfully publish
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);

  PERFORM public.publish_announcement(v_ann_id);

  PERFORM ok(
    EXISTS (SELECT 1 FROM public.announcements WHERE id = v_ann_id AND published_at IS NOT NULL),
    'admin can successfully publish announcement'
  );

  RESET ROLE;
END $$;

SELECT * FROM finish();

ROLLBACK;
