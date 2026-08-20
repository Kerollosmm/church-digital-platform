-- supabase/tests/0063_service_role_grants_test.sql
-- Verify record_booking_payment RPC and service_role permissions

begin;
select plan(3);

-- Test 1: Function exists and is callable
select has_function('public', 'record_booking_payment', array['bigint', 'numeric', 'text'], 'record_booking_payment RPC should exist');

-- Test 2: Negative test - anon cannot call record_booking_payment
set local role anon;
select throws_ok(
  $$ select public.record_booking_payment(1, 100, 'test') $$,
  '42501',
  null,
  'anon should be forbidden from calling record_booking_payment'
);

-- Test 3: Table grants for service_role
set local role postgres;
select ok(
  has_table_privilege('service_role', 'public.payments', 'INSERT'),
  'service_role should have INSERT on public.payments'
);

select * from finish();
rollback;
