-- 0064_event_booking_schema_test.sql
\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS pgtap;
BEGIN;
SELECT no_plan();

SELECT has_table('public', 'venues_resources', 'venues_resources table exists');
SELECT has_table('public', 'event_types', 'event_types table exists');
SELECT has_table('public', 'extra_services', 'extra_services table exists');
SELECT has_table('public', 'event_type_extra_services', 'event_type_extra_services table exists');
SELECT has_table('public', 'booking_extra_services', 'booking_extra_services table exists');
SELECT has_table('public', 'event_resource_bookings', 'event_resource_bookings table exists');
SELECT has_table('public', 'payment_audit_logs', 'payment_audit_logs table exists');

SELECT * FROM finish();
ROLLBACK;
