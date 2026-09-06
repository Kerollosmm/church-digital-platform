\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;

SELECT plan(16);

-- Setup: Ensure service exists for FK
INSERT INTO public.services (id, tenant_id, title_ar) OVERRIDING SYSTEM VALUE
VALUES (9957, 1, 'خدمة الاختبارات')
ON CONFLICT (id) DO NOTHING;

-- Setup: Ensure user and slot exist for bookings
INSERT INTO public.service_slots (id, tenant_id, service_id, starts_at, ends_at, capacity, price) OVERRIDING SYSTEM VALUE
VALUES (9957, 1, 9957, now() + interval '10 days', now() + interval '10 days 1 hour', 10, 0)
ON CONFLICT (id) DO NOTHING;

-- ==============================================================================
-- Rejection Contracts (throws_ok)
-- ==============================================================================

-- 1. service_slots: ends_at = starts_at
SELECT throws_ok(
  $$ INSERT INTO public.service_slots (tenant_id, service_id, starts_at, ends_at, capacity, price)
     VALUES (1, 9957, '2026-09-01 10:00:00+00', '2026-09-01 10:00:00+00', 10, 0) $$,
  '23514',
  NULL,
  'service_slots with ends_at = starts_at rejected by service_slots_time_order_chk'
);

-- 2. service_slots: ends_at < starts_at (with schedule_range populated)
SELECT throws_ok(
  $$ INSERT INTO public.service_slots (tenant_id, service_id, starts_at, ends_at, capacity, price, schedule_range)
     VALUES (1, 9957, '2026-09-01 11:00:00+00', '2026-09-01 10:00:00+00', 10, 0, tstzrange('2026-09-01 10:00:00+00', '2026-09-01 11:00:00+00')) $$,
  '23514',
  NULL,
  'service_slots with ends_at < starts_at rejected by service_slots_time_order_chk'
);

-- 3. service_slots: ends_at < starts_at (with schedule_range NULL)
SELECT throws_ok(
  $$ INSERT INTO public.service_slots (tenant_id, service_id, starts_at, ends_at, capacity, price, schedule_range)
     VALUES (1, 9957, '2026-09-01 11:00:00+00', '2026-09-01 10:00:00+00', 10, 0, NULL) $$,
  '23514',
  NULL,
  'service_slots with ends_at < starts_at and schedule_range NULL rejected by service_slots_time_order_chk'
);

-- 4. service_slots: capacity = -1
SELECT throws_ok(
  $$ INSERT INTO public.service_slots (tenant_id, service_id, starts_at, ends_at, capacity, price)
     VALUES (1, 9957, '2026-09-01 10:00:00+00', '2026-09-01 11:00:00+00', -1, 0) $$,
  '23514',
  NULL,
  'service_slots with capacity = -1 rejected by service_slots_capacity_nonneg_chk'
);

-- 5. service_slots: price = -1
SELECT throws_ok(
  $$ INSERT INTO public.service_slots (tenant_id, service_id, starts_at, ends_at, capacity, price)
     VALUES (1, 9957, '2026-09-01 10:00:00+00', '2026-09-01 11:00:00+00', 10, -1) $$,
  '23514',
  NULL,
  'service_slots with price = -1 rejected by service_slots_price_nonneg_chk'
);

-- 6. bookings: seat_count = 0
SELECT throws_ok(
  $$ INSERT INTO public.bookings (tenant_id, slot_id, user_id, status, seat_count)
     VALUES (1, 9957, 'aaaaaaaa-0000-0000-0000-000000000001', 'PENDING_PAYMENT', 0) $$,
  '23514',
  NULL,
  'bookings with seat_count = 0 rejected by bookings_seat_count_min_chk'
);

-- 7. bookings: seat_count = -1
SELECT throws_ok(
  $$ INSERT INTO public.bookings (tenant_id, slot_id, user_id, status, seat_count)
     VALUES (1, 9957, 'aaaaaaaa-0000-0000-0000-000000000001', 'PENDING_PAYMENT', -1) $$,
  '23514',
  NULL,
  'bookings with seat_count = -1 rejected by bookings_seat_count_min_chk'
);

-- 8. payments: amount = -1
SELECT throws_ok(
  $$ INSERT INTO public.payments (tenant_id, amount, status)
     VALUES (1, -1, 'CREATED') $$,
  '23514',
  NULL,
  'payments with amount = -1 rejected by payments_amount_nonneg_chk'
);

-- 9. media_assets: content_type set, content_id NULL
SELECT throws_ok(
  $$ INSERT INTO public.media_assets (tenant_id, bucket, storage_path, content_type, content_id, alt_text_ar)
     VALUES (1, 'church_media', 'test/p1.jpg', 'announcement', NULL, 'نص بديل') $$,
  '23514',
  NULL,
  'media_assets with content_type set and content_id null rejected by media_assets_polymorphic_chk'
);

-- 10. media_assets: content_type NULL, content_id set
SELECT throws_ok(
  $$ INSERT INTO public.media_assets (tenant_id, bucket, storage_path, content_type, content_id, alt_text_ar)
     VALUES (1, 'church_media', 'test/p2.jpg', NULL, 1, 'نص بديل') $$,
  '23514',
  NULL,
  'media_assets with content_type null and content_id set rejected by media_assets_polymorphic_chk'
);

-- ==============================================================================
-- Acceptance Contracts (lives_ok)
-- ==============================================================================

-- 11. service_slots: ends_at > starts_at, capacity = 0, price = 0
SELECT lives_ok(
  $$ INSERT INTO public.service_slots (tenant_id, service_id, starts_at, ends_at, capacity, price)
     VALUES (1, 9957, '2026-09-02 10:00:00+00', '2026-09-02 11:00:00+00', 0, 0) $$,
  'service_slots with ends_at > starts_at, capacity = 0, price = 0 accepted'
);

-- 12. bookings: seat_count = 1
SELECT lives_ok(
  $$ INSERT INTO public.bookings (tenant_id, slot_id, user_id, status, seat_count)
     VALUES (1, 9957, 'aaaaaaaa-0000-0000-0000-000000000001', 'PENDING_PAYMENT', 1) $$,
  'bookings with seat_count = 1 accepted'
);

-- 13. payments: amount = 0
SELECT lives_ok(
  $$ INSERT INTO public.payments (tenant_id, amount, status)
     VALUES (1, 0, 'CREATED') $$,
  'payments with amount = 0 accepted'
);

-- 14. media_assets: both content_type and content_id NULL
SELECT lives_ok(
  $$ INSERT INTO public.media_assets (tenant_id, bucket, storage_path, content_type, content_id, is_decorative)
     VALUES (1, 'church_media', 'test/decor.jpg', NULL, NULL, true) $$,
  'media_assets with both polymorphic columns NULL accepted'
);

-- 15. media_assets: both content_type and content_id set
SELECT lives_ok(
  $$ INSERT INTO public.media_assets (tenant_id, bucket, storage_path, content_type, content_id, alt_text_ar)
     VALUES (1, 'announcement_images', 'test/ann.jpg', 'announcement', 1, 'صورة الإعلان') $$,
  'media_assets with both polymorphic columns populated accepted'
);

-- 16. bookings: every value of booking_status accepted
SELECT lives_ok(
  $$
  INSERT INTO public.bookings (tenant_id, slot_id, user_id, status, seat_count) VALUES
    (1, 9957, 'aaaaaaaa-0000-0000-0000-000000000001', 'PENDING_PAYMENT', 1),
    (1, 9957, 'aaaaaaaa-0000-0000-0000-000000000001', 'AWAITING_CALL', 1),
    (1, 9957, 'aaaaaaaa-0000-0000-0000-000000000001', 'CONFIRMED', 1),
    (1, 9957, 'aaaaaaaa-0000-0000-0000-000000000001', 'COMPLETED', 1),
    (1, 9957, 'aaaaaaaa-0000-0000-0000-000000000001', 'CANCELLED', 1),
    (1, 9957, 'aaaaaaaa-0000-0000-0000-000000000001', 'RESCHEDULED', 1);
  $$,
  'all booking_status enum values accepted'
);

SELECT * FROM finish();

ROLLBACK;
