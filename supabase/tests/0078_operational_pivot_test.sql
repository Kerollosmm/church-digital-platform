-- ==============================================================================
-- 0078_operational_pivot_test.sql
-- Test suite for Operational Pivot (Sacramental Track, Activities, Cashier)
-- ==============================================================================

BEGIN;
SELECT plan(12);

-- 1. Schema & Column Assertions
SELECT has_column('public', 'event_types', 'category', 'event_types has category column');
SELECT has_column('public', 'event_types', 'required_documents_ar', 'event_types has required_documents_ar column');
SELECT has_function('public', 'admin_quick_cash_collect', ARRAY['uuid', 'bigint', 'text'], 'admin_quick_cash_collect RPC exists');

-- 2. Setup Fixtures
INSERT INTO auth.users (id, email, phone)
VALUES 
  ('11111111-1111-1111-1111-111111111111', 'admin_pivot@church.org', '+201000000091'),
  ('22222222-2222-2222-2222-222222222222', 'member_pivot@church.org', '+201000000092'),
  ('33333333-3333-3333-3333-333333333333', 'servant_pivot@church.org', '+201000000093')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.users (id, name, phone, role)
VALUES 
  ('11111111-1111-1111-1111-111111111111', 'Admin Pivot', '+201000000091', 'ADMIN'),
  ('22222222-2222-2222-2222-222222222222', 'Member Pivot', '+201000000092', 'USER'),
  ('33333333-3333-3333-3333-333333333333', 'Servant Pivot', '+201000000093', 'USER')
ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role;

-- Insert Sacrament and Activity Event Types
INSERT INTO public.event_types (id, name_ar, base_price_piastres, default_duration_minutes, category, required_documents_ar)
VALUES 
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'سر الإكليل المقدس', 50000, 120, 'SACRAMENT', ARRAY['شهادة خلو موانع', 'شهادة دورة المشورة الأسرية']),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'رحلة دير الأنبا بيشوي', 15000, 360, 'ACTIVITY', '{}')
ON CONFLICT (id) DO UPDATE SET 
  category = EXCLUDED.category,
  required_documents_ar = EXCLUDED.required_documents_ar;

-- Test Category and Documents
SELECT is(
  (SELECT category FROM public.event_types WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'SACRAMENT',
  'Wedding is categorized as SACRAMENT'
);

SELECT is(
  (SELECT array_length(required_documents_ar, 1) FROM public.event_types WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2,
  'Wedding has 2 required documents'
);

SELECT is(
  (SELECT category FROM public.event_types WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  'ACTIVITY',
  'Trip is categorized as ACTIVITY'
);

-- Insert Event Booking for Member
INSERT INTO public.event_bookings (
  id, customer_id, event_type_id, start_time, end_time, status, total_price_piastres, paid_amount_piastres
) VALUES (
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  '22222222-2222-2222-2222-222222222222',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  now() + interval '2 days',
  now() + interval '2 days 2 hours',
  'CONFIRMED',
  50000,
  0
) ON CONFLICT (id) DO NOTHING;

-- 3. Test admin_quick_cash_collect Authorization Denial
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '22222222-2222-2222-2222-222222222222'; -- regular user

SELECT throws_ok(
  $$ SELECT public.admin_quick_cash_collect('cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid, 50000::bigint) $$,
  '42501',
  NULL,
  'Non-admin cannot execute admin_quick_cash_collect'
);

-- 4. Test admin_quick_cash_collect as Admin
SET LOCAL "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111'; -- admin

SELECT lives_ok(
  $$ SELECT public.admin_quick_cash_collect('cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid, 50000::bigint, 'إيصال خزينة معتمد'::text) $$,
  'Admin successfully collects quick cash'
);

-- Verify status is now PAID and paid_amount_piastres = 50000
SELECT is(
  (SELECT status::text FROM public.event_bookings WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  'PAID',
  'Booking status advanced to PAID after quick cash collection'
);

SELECT is(
  (SELECT paid_amount_piastres FROM public.event_bookings WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  50000::bigint,
  'Booking paid_amount_piastres updated to 50000'
);

-- Verify payment audit log inserted
SELECT is(
  (SELECT count(*)::int FROM public.payment_audit_logs WHERE booking_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc' AND action = 'CASH_COLLECTED'),
  1,
  'Payment audit log created with action CASH_COLLECTED'
);

-- Verify WhatsApp outbox message created
SELECT is(
  (SELECT count(*)::int FROM public.event_outbox WHERE handler_type = 'WHATSAPP' AND payload->>'template_name' = 'event_booking_payment_received'),
  1,
  'WhatsApp outbox message enqueued for event_booking_payment_received'
);

SELECT * FROM finish();
ROLLBACK;
