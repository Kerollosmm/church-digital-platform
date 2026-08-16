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

-- 1. idx_bookings_slot_id should exist
SELECT tests.expect(
  EXISTS(SELECT 1 FROM pg_indexes WHERE tablename = 'bookings' AND indexname = 'idx_bookings_slot_id'),
  'idx_bookings_slot_id should exist'
);

-- 2. idx_payments_booking_id should exist
SELECT tests.expect(
  EXISTS(SELECT 1 FROM pg_indexes WHERE tablename = 'payments' AND indexname = 'idx_payments_booking_id'),
  'idx_payments_booking_id should exist'
);

-- Setup user fixture
INSERT INTO auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'test-user@test.local', '+201000000001',
        '{}', '{"name":"Test User"}', now(), now())
ON CONFLICT (id) DO NOTHING;
UPDATE public.users SET role = 'USER', tenant_id = 1 WHERE id = '00000000-0000-0000-0000-000000000001';

-- 3. Multi-seat restoration test
INSERT INTO public.services (id, title_ar, tenant_id) OVERRIDING SYSTEM VALUE VALUES (99981, 'Test Service', 1) ON CONFLICT DO NOTHING;
INSERT INTO public.service_slots (id, service_id, starts_at, ends_at, capacity, remaining_capacity, price, tenant_id)
OVERRIDING SYSTEM VALUE
VALUES (99981, 99981, now() + interval '1 day', now() + interval '1 day 2 hours', 50, 47, 0, 1) ON CONFLICT DO NOTHING;

INSERT INTO public.bookings (id, slot_id, user_id, status, seat_count, paid_amount, tenant_id)
OVERRIDING SYSTEM VALUE
VALUES (99981, 99981, '00000000-0000-0000-0000-000000000001', 'CONFIRMED', 3, 0, 1) ON CONFLICT DO NOTHING;

UPDATE public.bookings SET status = 'CANCELLED' WHERE id = 99981;

SELECT tests.expect(
  (SELECT remaining_capacity FROM public.service_slots WHERE id = 99981) = 50,
  'Remaining capacity should restore full seat_count (3 seats) on cancellation'
);

-- 4. slot_utilization_monthly should have tenant_id column
SELECT tests.expect(
  EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name = 'slot_utilization_monthly' AND column_name = 'tenant_id'),
  'slot_utilization_monthly should have tenant_id column'
);

-- 5. idx_bookings_pending_lock should exist
SELECT tests.expect(
  EXISTS(SELECT 1 FROM pg_indexes WHERE tablename = 'bookings' AND indexname = 'idx_bookings_pending_lock'),
  'idx_bookings_pending_lock should exist'
);

-- 6. bookings table should be omitted from supabase_realtime publication
SELECT tests.expect(
  NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'bookings'),
  'bookings table should be omitted from supabase_realtime publication'
);

ROLLBACK;
