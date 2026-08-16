BEGIN;

-- supabase/tests/0022_analytics_aggregates_test.sql
DO $$
DECLARE v_slots_total int; v_slots_booked int; v_bookings_total int; v_conf int;
        v_total_paid numeric; v_total_refunded numeric; v_count_paid int;
BEGIN
  -- fixtures: 1 service, 2 slots this month (capacity 50 each), 1 CONFIRMED + 1 PENDING_PAYMENT booking, 1 PAID + 1 REFUNDED payment
  DELETE FROM public.payments WHERE booking_id IN (SELECT id FROM public.bookings WHERE slot_id IN (SELECT id FROM public.service_slots WHERE service_id = 901) OR id IN (901, 902));
  DELETE FROM public.bookings WHERE slot_id IN (SELECT id FROM public.service_slots WHERE service_id = 901) OR id IN (901, 902);
  DELETE FROM public.service_slots WHERE service_id = 901 OR id IN (901, 902);

  INSERT INTO public.services (id, title_ar, tenant_id)
    OVERRIDING SYSTEM VALUE
    VALUES (901, 'قداس اختبار', 1) ON CONFLICT DO NOTHING;
  INSERT INTO public.service_slots (id, service_id, starts_at, ends_at, capacity, price, tenant_id)
    OVERRIDING SYSTEM VALUE
    VALUES (901, 901, date_trunc('month', now() AT TIME ZONE 'Africa/Cairo') + interval '1 day',
            date_trunc('month', now() AT TIME ZONE 'Africa/Cairo') + interval '1 day 2 hours', 50, 0, 1),
           (902, 901, date_trunc('month', now() AT TIME ZONE 'Africa/Cairo') + interval '8 days',
            date_trunc('month', now() AT TIME ZONE 'Africa/Cairo') + interval '8 days 2 hours', 50, 0, 1)
    ON CONFLICT DO NOTHING;
  INSERT INTO public.bookings (id, slot_id, user_id, status, tenant_id)
    OVERRIDING SYSTEM VALUE
    VALUES (901, 901, (SELECT id FROM auth.users LIMIT 1), 'CONFIRMED', 1),
           (902, 902, (SELECT id FROM auth.users LIMIT 1), 'PENDING_PAYMENT', 1)
    ON CONFLICT DO NOTHING;
  INSERT INTO public.payments (id, booking_id, amount, status, tenant_id)
    OVERRIDING SYSTEM VALUE
    VALUES (901, 901, 100, 'PAID', 1),
           (902, 902, 50, 'REFUNDED', 1)
    ON CONFLICT DO NOTHING;

  PERFORM public.materialize_analytics();

  SELECT s.slots_total, s.slots_booked INTO v_slots_total, v_slots_booked
    FROM public.slot_utilization_monthly s
    WHERE s.month = (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date AND s.service_id = 901 LIMIT 1;
  IF v_slots_total != 2 OR v_slots_booked != 1 THEN
    RAISE EXCEPTION 'FAIL: utilization %, %', v_slots_total, v_slots_booked;
  END IF;

  SELECT b.bookings_total, (b.by_status->>'CONFIRMED')::int INTO v_bookings_total, v_conf
    FROM public.bookings_monthly b
    WHERE b.month = (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date AND b.service_id = 901 LIMIT 1;
  IF v_bookings_total != 2 OR v_conf != 1 THEN
    RAISE EXCEPTION 'FAIL: bookings %, confirmed %', v_bookings_total, v_conf;
  END IF;

  SELECT p.total_paid, p.total_refunded, p.count_paid INTO v_total_paid, v_total_refunded, v_count_paid
    FROM public.payments_monthly p
    WHERE p.month = (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date LIMIT 1;
  IF v_total_paid < 100 OR v_total_refunded < 50 OR v_count_paid < 1 THEN
    RAISE EXCEPTION 'FAIL: payments %, %, %', v_total_paid, v_total_refunded, v_count_paid;
  END IF;

  -- idempotent: second run must not duplicate rows
  PERFORM public.materialize_analytics();
  IF (SELECT count(*) FROM public.slot_utilization_monthly
      WHERE month = (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date AND service_id = 901) > 1 THEN
    RAISE EXCEPTION 'FAIL: duplicates';
  END IF;

  RAISE NOTICE 'PASS: materialize_analytics';
END $$;

ROLLBACK;
