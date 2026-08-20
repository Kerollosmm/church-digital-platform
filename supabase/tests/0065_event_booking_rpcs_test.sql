-- 0065_event_booking_rpcs_test.sql
\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS pgtap;
BEGIN;
SELECT no_plan();

SELECT has_function('public', 'submit_event_booking', ARRAY['bigint', 'timestamptz', 'jsonb', 'text']);
SELECT has_function('public', 'admin_confirm_booking', ARRAY['bigint', 'bigint', 'timestamptz', 'integer']);
SELECT has_function('public', 'admin_reject_booking', ARRAY['bigint', 'text']);
SELECT has_function('public', 'admin_record_cash_payment', ARRAY['bigint', 'bigint', 'text', 'text']);

SELECT * FROM finish();
ROLLBACK;
