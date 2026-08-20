\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;

SELECT plan(3);

-- 1. All 4 FKs have confdeltype = 'r' (RESTRICT)
SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_constraint
    WHERE conname IN (
      'bookings_user_id_fkey',
      'complaints_user_id_fkey',
      'complaints_assigned_to_fkey',
      'waiting_list_user_id_fkey'
    )
    AND confdeltype = 'r'
  ),
  4,
  'all 4 user FK constraints have confdeltype = r (RESTRICT)'
);

-- 2. Hard delete on user with booking raises 23503 (FK violation)
DO $$
DECLARE
  v_uid uuid := '00000000-0000-0000-0000-000000000061'::uuid;
  v_denied boolean := false;
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email, phone, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES (v_uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u61@test.local', '+201061616161', crypt('pw', gen_salt('bf')), now(), '{"provider":"email"}', '{}', now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.users (id, tenant_id, phone, name, role)
  VALUES (v_uid, 1, '+201061616161', 'User 61', 'USER')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.services (id, tenant_id, title_ar) OVERRIDING SYSTEM VALUE
  VALUES (9961, 1, 'خدمة الحذف')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.service_slots (id, tenant_id, service_id, starts_at, ends_at, capacity, price) OVERRIDING SYSTEM VALUE
  VALUES (9961, 1, 9961, now() + interval '10 days', now() + interval '10 days 1 hour', 10, 0)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.bookings (tenant_id, slot_id, user_id, status, seat_count)
  VALUES (1, 9961, v_uid, 'CONFIRMED', 1);

  BEGIN
    DELETE FROM public.users WHERE id = v_uid;
    v_denied := false;
  EXCEPTION WHEN foreign_key_violation THEN
    v_denied := true;
  END;

  PERFORM ok(v_denied, 'DELETE FROM public.users on user with active booking raises foreign_key_violation (23503)');
END $$;

-- 3. Soft delete (deleted_at = now()) on public.users works cleanly
SELECT lives_ok(
  $$ UPDATE public.users SET deleted_at = now() WHERE id = '00000000-0000-0000-0000-000000000061'::uuid $$,
  'soft delete on public.users succeeds without constraint violation'
);

SELECT * FROM finish();

ROLLBACK;
