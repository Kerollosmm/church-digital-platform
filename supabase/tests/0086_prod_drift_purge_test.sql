BEGIN;
SELECT plan(44);

-- v_services reified
SELECT has_view('public', 'v_services', 'v_services view exists');
SELECT has_column('public', 'v_services', 'next_slot_starts_at', 'v_services.next_slot_starts_at exists');
SELECT has_column('public', 'v_services', 'price_from', 'v_services.price_from exists');
SELECT has_column('public', 'v_services', 'tenant_id', 'v_services.tenant_id exists');

-- drift tables gone
SELECT hasnt_table('public', 'alerts', 'alerts dropped');
SELECT hasnt_table('public', 'attendance', 'attendance dropped');
SELECT hasnt_table('public', 'clergy_profiles', 'clergy_profiles dropped');
SELECT hasnt_table('public', 'family_members', 'family_members dropped');
SELECT hasnt_table('public', 'households', 'households dropped');
SELECT hasnt_table('public', 'members', 'members dropped');
SELECT hasnt_table('public', 'visits', 'visits dropped');
SELECT hasnt_table('public', 'refund_requests', 'refund_requests dropped');
SELECT hasnt_table('public', 'venues', 'venues dropped');
SELECT hasnt_table('public', 'whatsapp_outbox', 'whatsapp_outbox dropped');

-- drift functions gone
SELECT hasnt_function('public', 'admin_apply_pastoral_fee_waiver', ARRAY['bigint','bigint','text','text'], 'admin_apply_pastoral_fee_waiver dropped');
SELECT hasnt_function('public', 'assign_clergy_to_event', ARRAY['bigint','bigint'], 'assign_clergy_to_event dropped');
SELECT hasnt_function('public', 'book_family_slots', ARRAY['bigint','bigint[]','boolean'], 'book_family_slots dropped');
SELECT hasnt_function('public', 'cancel_event_booking', ARRAY['bigint','text'], 'cancel_event_booking dropped');
SELECT hasnt_function('public', 'get_clergy_daily_itinerary', ARRAY['bigint','date'], 'get_clergy_daily_itinerary dropped');
SELECT hasnt_function('public', 'manage_family_members', ARRAY['text','bigint','text','text','text','date','text'], 'manage_family_members dropped');
SELECT hasnt_function('public', 'rapid_emergency_funeral_booking', ARRAY['text','text','bigint','bigint','timestamptz','integer','text'], 'rapid_emergency_funeral_booking dropped');
SELECT hasnt_function('public', 'record_cash_payment', ARRAY['bigint','integer','text'], 'record_cash_payment dropped');
SELECT hasnt_function('public', 'set_updated_at', ARRAY[]::text[], 'set_updated_at dropped');
SELECT hasnt_function('public', 'superadmin_create_extra_service', ARRAY['text','text','text','text','text','bigint','boolean','integer'], 'superadmin_create_extra_service dropped');
SELECT hasnt_function('public', 'superadmin_link_service_to_event_type', ARRAY['bigint','bigint','boolean'], 'superadmin_link_service_to_event_type dropped');
SELECT hasnt_function('public', 'superadmin_toggle_extra_service_status', ARRAY['bigint','boolean'], 'superadmin_toggle_extra_service_status dropped');
SELECT hasnt_function('public', 'superadmin_update_extra_service', ARRAY['bigint','text','text','text','text','text','bigint','boolean','integer'], 'superadmin_update_extra_service dropped');
SELECT hasnt_function('public', 'superadmin_upsert_event_type', ARRAY['bigint','text','bigint','boolean'], 'superadmin_upsert_event_type dropped');
SELECT hasnt_function('public', 'superadmin_upsert_extra_service', ARRAY['bigint','text','bigint','boolean','boolean'], 'superadmin_upsert_extra_service dropped');
SELECT hasnt_function('public', 'admin_record_cash_payment', ARRAY['bigint','integer','text','text'], 'admin_record_cash_payment(bigint,integer,text,text) dropped');
SELECT hasnt_function('public', 'admin_record_cash_payment', ARRAY['bigint','bigint','text','text'], 'admin_record_cash_payment(bigint,bigint,text,text) dropped');

-- payments drift columns gone
SELECT hasnt_column('public', 'payments', 'event_booking_id', 'payments.event_booking_id dropped');
SELECT hasnt_column('public', 'payments', 'method', 'payments.method dropped');
SELECT hasnt_column('public', 'payments', 'recorded_by', 'payments.recorded_by dropped');
SELECT hasnt_column('public', 'payments', 'received_at', 'payments.received_at dropped');
SELECT hasnt_column('public', 'payments', 'receipt_reference', 'payments.receipt_reference dropped');

-- drift enums gone
SELECT hasnt_type('public', 'alert_type', 'alert_type dropped');
SELECT hasnt_type('public', 'attendance_method', 'attendance_method dropped');
SELECT hasnt_type('public', 'member_status', 'member_status dropped');
SELECT hasnt_type('public', 'payment_method', 'payment_method dropped');
SELECT hasnt_type('public', 'pricing_mode', 'pricing_mode dropped');

-- complaints policy: repo version present, drift version absent
SELECT is(
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'complaints'
      AND policyname = 'complaints_admin_assign'),
  1::bigint,
  'complaints_admin_assign policy exists'
);
SELECT is(
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'complaints'
      AND policyname = 'complaints assign write'),
  0::bigint,
  'drift policy complaints assign write dropped'
);

-- H-3: all 19 functions carry the hardened search_path
WITH expected(sig, sp) AS (VALUES
  ('admin_pin_status()', 'search_path=public, extensions, pg_temp'),
  ('cancel_booking(bigint)', 'search_path=public, pg_temp'),
  ('complete_booking(bigint)', 'search_path=public, pg_temp'),
  ('confirm_booking(bigint)', 'search_path=public, pg_temp'),
  ('decrypt_complaint(bigint)', 'search_path=public, extensions, pg_temp'),
  ('emergency_override(bigint,bigint,boolean)', 'search_path=public, pg_temp'),
  ('enqueue_fcm_booking_status_push()', 'search_path=public, pg_temp'),
  ('expire_stale_bookings()', 'search_path=public, pg_temp'),
  ('join_waiting_list(bigint)', 'search_path=public, pg_temp'),
  ('manual_book(bigint,text,boolean,text)', 'search_path=public, pg_temp'),
  ('materialize_analytics()', 'search_path=public, pg_temp'),
  ('promote_waiting_list(bigint)', 'search_path=public, pg_temp'),
  ('reset_admin_pin(uuid)', 'search_path=public, extensions, pg_temp'),
  ('set_admin_pin(text)', 'search_path=public, extensions, pg_temp'),
  ('submit_complaint_secure(text,text)', 'search_path=public, extensions, pg_temp'),
  ('sync_offline_mutations(jsonb)', 'search_path=public, extensions, pg_temp'),
  ('transition_booking_status(bigint,booking_status,text,text,jsonb)', 'search_path=public, pg_temp'),
  ('update_fcm_token(text)', 'search_path=public, pg_temp'),
  ('verify_admin_pin(text)', 'search_path=public, extensions, pg_temp')
)
SELECT is(
  (SELECT count(*)
   FROM expected e
   JOIN pg_proc p ON p.oid = ('public.' || e.sig)::regprocedure
   WHERE e.sp = ANY (p.proconfig)),
  19::bigint,
  'all 19 SECURITY DEFINER functions carry hardened search_path'
);

SELECT * FROM finish();
ROLLBACK;
