-- supabase/tests/0022_analytics_aggregates_test.sql
DO $$
DECLARE slots_total int; slots_booked int; bookings_total int; conf int;
        total_paid numeric; total_refunded numeric; count_paid int;
BEGIN
  -- fixtures: 1 service, 2 slots this month (capacity 50 each), 1 CONFIRMED + 1 PENDING_PAYMENT booking, 1 PAID + 1 REFUNDED payment
  INSERT INTO public.services (id, title_ar, tenant_id)
    VALUES (901, 'قداس اختبار', '00000000-0000-0000-0000-000000000001') ON CONFLICT DO NOTHING;
  INSERT INTO public.service_slots (id, service_id, starts_at, ends_at, capacity, price, tenant_id)
    VALUES (901, 901, date_trunc('month', now() AT TIME ZONE 'Africa/Cairo') + interval '1 day',
            date_trunc('month', now() AT TIME ZONE 'Africa/Cairo') + interval '1 day 2 hours', 50, 0, 1),
           (902, 901, date_trunc('month', now() AT TIME ZONE 'Africa/Cairo') + interval '8 days',
            date_trunc('month', now() AT TIME ZONE 'Africa/Cairo') + interval '8 days 2 hours', 50, 0, 1)
    ON CONFLICT DO NOTHING;
  INSERT INTO public.bookings (id, slot_id, user_id, status, tenant_id)
    VALUES (901, 901, (SELECT id FROM auth.users LIMIT 1), 'CONFIRMED', 1),
           (902, 902, (SELECT id FROM auth.users LIMIT 1), 'PENDING_PAYMENT', 1)
    ON CONFLICT DO NOTHING;
  INSERT INTO public.payments (id, booking_id, amount, status, tenant_id)
    VALUES (901, 901, 100, 'PAID', 1),
           (902, 902, 50, 'REFUNDED', 1)
    ON CONFLICT DO NOTHING;

  PERFORM public.materialize_analytics();

  SELECT slots_total, slots_booked INTO slots_total, slots_booked
    FROM public.slot_utilization_monthly
    WHERE month = (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date LIMIT 1;
  IF slots_total != 2 OR slots_booked != 1 THEN
    RAISE EXCEPTION 'FAIL: utilization %, %', slots_total, slots_booked;
  END IF;

  SELECT bookings_total, (by_status->>'CONFIRMED')::int INTO bookings_total, conf
    FROM public.bookings_monthly
    WHERE month = (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date LIMIT 1;
  IF bookings_total != 2 OR conf != 1 THEN
    RAISE EXCEPTION 'FAIL: bookings %, confirmed %', bookings_total, conf;
  END IF;

  SELECT total_paid, total_refunded, count_paid INTO total_paid, total_refunded, count_paid
    FROM public.payments_monthly
    WHERE month = (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date LIMIT 1;
  IF total_paid != 100 OR total_refunded != 50 OR count_paid != 1 THEN
    RAISE EXCEPTION 'FAIL: payments %, %, %', total_paid, total_refunded, count_paid;
  END IF;

  -- idempotent: second run must not duplicate rows
  PERFORM public.materialize_analytics();
  IF (SELECT count(*) FROM public.slot_utilization_monthly
      WHERE month = (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date) > 1 THEN
    RAISE EXCEPTION 'FAIL: duplicates';
  END IF;

  RAISE NOTICE 'PASS: materialize_analytics';
END $$;
