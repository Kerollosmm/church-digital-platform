\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;

SELECT plan(4);

-- Test 1: Insert auth.users with valid phone creates mirrored public.users row
INSERT INTO auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES ('bbbbbbbb-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'testuser1@church.test', '+201011111111',
        '{}'::jsonb, json_build_object('name', 'مستخدم تجريبي')::jsonb, now(), now());

SELECT results_eq(
  $$ SELECT phone, name FROM public.users WHERE id = 'bbbbbbbb-0000-0000-0000-000000000001' $$,
  $$ VALUES ('+201011111111'::text, 'مستخدم تجريبي'::text) $$,
  'auth.users insert with phone creates matching public.users row'
);

-- Test 2: Insert auth.users with NULL phone raises error
SELECT throws_ok(
  $$ INSERT INTO auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
     VALUES ('bbbbbbbb-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
             'authenticated', 'authenticated', 'nophone@church.test', NULL,
             '{}'::jsonb, json_build_object('name', 'بدون هاتف')::jsonb, now(), now()) $$,
  NULL,
  NULL,
  'auth.users insert with NULL phone raises exception'
);

-- Test 3: Insert auth.users with empty string phone raises error
SELECT throws_ok(
  $$ INSERT INTO auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
     VALUES ('bbbbbbbb-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
             'authenticated', 'authenticated', 'emptyphone@church.test', '',
             '{}'::jsonb, json_build_object('name', 'هاتف فارغ')::jsonb, now(), now()) $$,
  NULL,
  NULL,
  'auth.users insert with empty phone raises exception'
);

-- Test 4: Verify zero users have UUID-format phone numbers
SELECT is(
  (SELECT count(*)::integer FROM public.users WHERE phone ~* '^[0-9a-f]{8}-[0-9a-f]{4}-'),
  0,
  'zero public.users rows have UUID formatted phone numbers'
);

SELECT * FROM finish();

ROLLBACK;
