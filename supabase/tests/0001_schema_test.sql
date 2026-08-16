\set ON_ERROR_STOP on

BEGIN;

create schema if not exists tests;
create or replace function tests.expect(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if not p_cond then raise exception 'FAIL: %', p_msg; end if;
end $$;

do $$
declare t text;
begin
  foreach t in array array['users','roles_permissions','priests','services','service_slots',
                          'bookings','payments','waiting_list','videos','video_purchases',
                          'complaints','announcements','audit_log','event_outbox',
                          'whatsapp_optins'] loop
    perform tests.expect(
      exists (select 1 from pg_tables where schemaname = 'public' and tablename = t),
      'table missing: ' || t);
  end loop;
  foreach t in array array['households','members','attendance','visits','alerts'] loop
    perform tests.expect(
      not exists (select 1 from pg_tables where schemaname = 'public' and tablename = t),
      'CMeeting table must not exist: ' || t);
  end loop;
end $$;

do $$
declare e text; v_count int;
begin
  foreach e in array array['app_role','booking_status','payment_status','video_privacy',
                          'complaint_status','event_handler_type','outbox_status'] loop
    perform tests.expect(
      exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
              where n.nspname = 'public' and t.typname = e and t.typtype = 'e'),
      'enum missing: ' || e);
  end loop;
  foreach e in array array['alert_type','attendance_method','member_status'] loop
    perform tests.expect(
      not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                  where n.nspname = 'public' and t.typname = e and t.typtype = 'e'),
      'CMeeting enum must not exist: ' || e);
  end loop;
  perform tests.expect(
    (select array_agg(e.enumlabel::text order by e.enumsortorder)
     from pg_enum e
     join pg_type t on t.oid = e.enumtypid
     join pg_namespace n on n.oid = t.typnamespace
     where n.nspname = 'public' and t.typname = 'app_role') = array['USER','ADMIN'],
    'app_role must contain exactly USER and ADMIN in canonical order');
  select count(*) into v_count from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'booking_status';
  perform tests.expect(v_count = 6, 'booking_status must have 6 values');
  select count(*) into v_count from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'video_privacy';
  perform tests.expect(v_count = 3, 'video_privacy must have 3 values (PUBLIC, UNLISTED, PRIVATE)');
  select count(*) into v_count from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'payment_status';
  perform tests.expect(v_count = 6, 'payment_status must have 6 values (CREATED,PAID,FAILED,REFUNDED,REFUND_PENDING,PENDING)');
end $$;

do $$
declare e text;
begin
  foreach e in array array['pg_cron','pg_net','supabase_vault'] loop
    perform tests.expect(exists (select 1 from pg_extension where extname = e),
      'extension missing: ' || e);
  end loop;
  perform tests.expect(not exists (select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'uq_active_booking_per_slot'),
    'lock index uq_active_booking_per_slot must NOT exist (breaks multi-seat slots)');
  perform tests.expect(exists (select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'bookings' and column_name = 'locked_until'),
    'bookings.locked_until missing');
  perform tests.expect(exists (select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'service_slots' and column_name = 'capacity'),
    'service_slots.capacity missing');
end $$;

ROLLBACK;
