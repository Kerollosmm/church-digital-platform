-- supabase/tests/0070_drop_paymob_stack_test.sql
-- 011 US5: Paymob stack deletion verification
-- Tests: record_webhook_payment absent, mark_payment_failed absent,
-- reconcile-payments cron unscheduled, PAYMOB_REFUND outbox rows purged,
-- payments.raw_webhook column dropped, create_pending_payment & apply_payment preserved.

begin;
select plan(7);

-- 1. record_webhook_payment is dropped
select is(
  (select count(*)::int from pg_proc where proname = 'record_webhook_payment'),
  0,
  'record_webhook_payment function does not exist in pg_proc'
);

-- 2. mark_payment_failed is dropped
select is(
  (select count(*)::int from pg_proc where proname = 'mark_payment_failed'),
  0,
  'mark_payment_failed function does not exist in pg_proc'
);

-- 3. reconcile-payments cron job is unscheduled
select is(
  (select count(*)::int from cron.job where jobname = 'reconcile-payments'),
  0,
  'reconcile-payments cron job is not scheduled'
);

-- 4. event_outbox has zero PAYMOB_REFUND rows
select is(
  (select count(*)::int from public.event_outbox where handler_type = 'PAYMOB_REFUND'),
  0,
  'event_outbox contains zero PAYMOB_REFUND rows'
);

-- 5. payments table has no raw_webhook column
select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public'
      and table_name = 'payments'
      and column_name = 'raw_webhook'),
  0,
  'raw_webhook column dropped from payments table'
);

-- 6. create_pending_payment is preserved
select is(
  (select count(*)::int from pg_proc where proname = 'create_pending_payment'),
  1,
  'create_pending_payment is preserved in pg_proc'
);

-- 7. apply_payment is preserved
select is(
  (select count(*)::int from pg_proc where proname = 'apply_payment'),
  1,
  'apply_payment is preserved in pg_proc'
);

select * from finish();
rollback;
