\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;

SELECT plan(11);

-- Setup fixtures
INSERT INTO public.services (id, tenant_id, title_ar) OVERRIDING SYSTEM VALUE
VALUES (9958, 1, 'خدمة الحالات')
ON CONFLICT (id) DO NOTHING;

-- 1. enum_range for slot_status
SELECT results_eq(
  $$ SELECT enum_range(NULL::public.slot_status)::text $$,
  $$ VALUES ('{OPEN,CLOSED}'::text) $$,
  'slot_status enum values are exactly {OPEN,CLOSED}'
);

-- 2. enum_range for waitlist_status
SELECT results_eq(
  $$ SELECT enum_range(NULL::public.waitlist_status)::text $$,
  $$ VALUES ('{WAITING,OFFERED}'::text) $$,
  'waitlist_status enum values are exactly {WAITING,OFFERED}'
);

-- 3. Invalid slot_status rejected
SELECT throws_ok(
  $$ INSERT INTO public.service_slots (tenant_id, service_id, starts_at, ends_at, capacity, price, status)
     VALUES (1, 9958, now() + interval '5 days', now() + interval '5 days 1 hour', 10, 0, 'PENDING'::public.slot_status) $$,
  '22P02',
  NULL,
  'invalid slot_status PENDING rejected with 22P02'
);

-- 4. Invalid waitlist_status rejected
SELECT throws_ok(
  $$ INSERT INTO public.waiting_list (tenant_id, slot_id, user_id, position, status)
     VALUES (1, 9958, 'aaaaaaaa-0000-0000-0000-000000000001', 1, 'EXPIRED'::public.waitlist_status) $$,
  '22P02',
  NULL,
  'invalid waitlist_status EXPIRED rejected with 22P02'
);

-- 5. Accepted slot_status CLOSED sent as string
SELECT lives_ok(
  $$ INSERT INTO public.service_slots (id, tenant_id, service_id, starts_at, ends_at, capacity, price, status) OVERRIDING SYSTEM VALUE
     VALUES (9958, 1, 9958, now() + interval '6 days', now() + interval '6 days 1 hour', 10, 0, 'CLOSED') $$,
  'service_slots with status CLOSED string accepted'
);

-- 6. Accepted waitlist_status OFFERED sent as string
SELECT lives_ok(
  $$ INSERT INTO public.waiting_list (tenant_id, slot_id, user_id, position, status)
     VALUES (1, 9958, 'aaaaaaaa-0000-0000-0000-000000000001', 1, 'OFFERED') $$,
  'waiting_list with status OFFERED string accepted'
);

-- 7. View permissions for anon on v_available_slots
SELECT ok(
  has_table_privilege('anon', 'public.v_available_slots', 'SELECT'),
  'anon role has SELECT privilege on public.v_available_slots'
);

-- 8. View permissions for authenticated on v_available_slots
SELECT ok(
  has_table_privilege('authenticated', 'public.v_available_slots', 'SELECT'),
  'authenticated role has SELECT privilege on public.v_available_slots'
);

-- 9. View permissions for anon on v_schedule_today
SELECT ok(
  has_table_privilege('anon', 'public.v_schedule_today', 'SELECT'),
  'anon role has SELECT privilege on public.v_schedule_today'
);

-- 10. View permissions for authenticated on v_schedule_today
SELECT ok(
  has_table_privilege('authenticated', 'public.v_schedule_today', 'SELECT'),
  'authenticated role has SELECT privilege on public.v_schedule_today'
);

-- 11. Admin update path: UPDATE service_slots SET status = 'CLOSED' returns CLOSED
SELECT results_eq(
  $$ UPDATE public.service_slots SET status = 'CLOSED' WHERE id = 9958 RETURNING status::text $$,
  $$ VALUES ('CLOSED'::text) $$,
  'admin update path: UPDATE service_slots SET status = CLOSED returns CLOSED'
);

SELECT * FROM finish();

ROLLBACK;
