-- supabase/tests/0045_audit_hardening_test.sql: regression test for 0045 audit hardening migration
BEGIN;
SELECT plan(13);

-- Setup fixtures
INSERT INTO auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'test-user@test.local', '+201000000001',
        '{}', '{"name":"Test User"}', now(), now())
ON CONFLICT (id) DO NOTHING;
UPDATE public.users SET role = 'USER', tenant_id = 1 WHERE id = '00000000-0000-0000-0000-000000000001';

INSERT INTO public.videos (id, title_ar, event_date, yt_url, price, privacy, tenant_id)
OVERRIDING SYSTEM VALUE
VALUES (999, 'Test Video', now(), 'https://youtu.be/test', 50, 'UNLISTED', 1)
ON CONFLICT (id) DO NOTHING;

-- 1. Test claim_event_outbox_batch column alignment
INSERT INTO public.event_outbox (handler_type, payload, status, next_attempt_at)
VALUES ('WHATSAPP'::public.event_handler_type, '{"phone": "+201000000001"}'::jsonb, 'PENDING', now() - interval '1 minute');

SELECT ok(
    (SELECT count(*)::int FROM public.claim_event_outbox_batch(10)) >= 1,
    'claim_event_outbox_batch should lease rows without schema error'
);

-- 2. Test video_purchases unique constraint
SELECT ok(
    EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conrelid = 'public.video_purchases'::regclass 
          AND contype = 'u'
    ),
    'video_purchases should have unique constraint'
);

-- 3. Test FK indexes exist
SELECT ok(
    EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 'bookings' AND indexname = 'idx_bookings_slot_id'),
    'idx_bookings_slot_id should exist'
);

SELECT ok(
    EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 'payments' AND indexname = 'idx_payments_booking_id'),
    'idx_payments_booking_id should exist'
);

-- 4. Test multi-seat cancellation capacity restoration
INSERT INTO public.services (id, title_ar) OVERRIDING SYSTEM VALUE VALUES (999, 'Test Service') ON CONFLICT DO NOTHING;
INSERT INTO public.service_slots (id, service_id, starts_at, ends_at, capacity, remaining_capacity)
OVERRIDING SYSTEM VALUE
VALUES (999, 999, now() + interval '1 day', now() + interval '1 day 2 hours', 10, 7) ON CONFLICT DO NOTHING;

INSERT INTO public.bookings (id, slot_id, user_id, status, seat_count, paid_amount)
OVERRIDING SYSTEM VALUE
VALUES (999, 999, '00000000-0000-0000-0000-000000000001', 'CONFIRMED', 3, 0) ON CONFLICT DO NOTHING;

UPDATE public.bookings SET status = 'CANCELLED' WHERE id = 999;

SELECT is(
    (SELECT remaining_capacity FROM public.service_slots WHERE id = 999),
    10,
    'Remaining capacity should restore full seat_count (3 seats) on cancellation'
);

-- 5. Test analytics tables have tenant_id
SELECT ok(
    EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'slot_utilization_monthly' AND column_name = 'tenant_id'
    ),
    'slot_utilization_monthly should have tenant_id column'
);

-- 6. Test partial index on bookings lock expiry
SELECT ok(
    EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 'bookings' AND indexname = 'idx_bookings_pending_lock'),
    'idx_bookings_pending_lock should exist'
);

-- 7. Test bookings removed from Realtime publication
SELECT ok(
    NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'bookings'
    ),
    'bookings table should be omitted from supabase_realtime publication'
);

-- 8. Negative auth: anon cannot execute claim_event_outbox_batch
DO $$
BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.claim_event_outbox_batch(10);
    RAISE EXCEPTION 'Anon must not execute claim_event_outbox_batch';
EXCEPTION
    WHEN insufficient_privilege THEN NULL;
END $$;
SELECT pass('Anon execution of claim_event_outbox_batch is denied');

-- 9. Negative auth: authenticated cannot execute claim_event_outbox_batch
DO $$
BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.claim_event_outbox_batch(10);
    RAISE EXCEPTION 'Authenticated must not execute claim_event_outbox_batch';
EXCEPTION
    WHEN insufficient_privilege THEN NULL;
END $$;
SELECT pass('Authenticated execution of claim_event_outbox_batch is denied');

-- 10. Negative auth: anon cannot execute purchase_video
DO $$
BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.purchase_video(1::bigint);
    RAISE EXCEPTION 'Anon must not execute purchase_video';
EXCEPTION
    WHEN insufficient_privilege THEN NULL;
END $$;
SELECT pass('Anon execution of purchase_video is denied');

-- 11. Negative auth: authenticated user without valid role cannot execute purchase_video
DO $$
DECLARE
    v_fake_user UUID := '00000000-0000-0000-0000-000000000099';
BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_fake_user, 'role', 'authenticated')::text, true);
    PERFORM public.purchase_video(1::bigint);
    RAISE EXCEPTION 'User with null/invalid role must not execute purchase_video';
EXCEPTION
    WHEN SQLSTATE '42501' THEN NULL;
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%FORBIDDEN%' THEN NULL;
        ELSE RAISE;
        END IF;
END $$;
SELECT pass('Authenticated user with invalid role execution of purchase_video is denied');

-- 13. Negative auth: p0_video_purchases_own_read tenant check
DO $$
DECLARE
    v_user UUID := '00000000-0000-0000-0000-000000000001';
    v_pay BIGINT;
    v_count INT;
BEGIN
    RESET ROLE;
    INSERT INTO public.payments (video_id, amount, status, tenant_id)
    VALUES (999, 50, 'PENDING', 999) RETURNING id INTO v_pay;

    INSERT INTO public.video_purchases (video_id, user_id, payment_id, tenant_id)
    VALUES (999, v_user, v_pay, 999) ON CONFLICT DO NOTHING;

    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.headers', json_build_object('x-tenant-id', '1')::text, true);

    SELECT count(*) INTO v_count FROM public.video_purchases WHERE video_id = 999;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'Foreign tenant video_purchases must be hidden from user';
    END IF;
END $$;
SELECT pass('Foreign tenant video_purchases is hidden under RLS');

SELECT * FROM finish();
ROLLBACK;
