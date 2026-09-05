-- 0082: audit_log UUID entity linkage + apply_payment search_path hardening
begin;

alter table public.audit_log
  add column if not exists entity_uuid uuid;

-- ---------------------------------------------------------------------------
-- 1. apply_payment: search_path corrected to public, pg_temp
-- ---------------------------------------------------------------------------
create or replace function public.apply_payment(p_payment_id bigint)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_pay public.payments;
  v_book public.bookings;
  v_phone text;
begin
  select * into v_pay from public.payments where id = p_payment_id for update;
  if v_pay is null then raise exception 'PAYMENT_NOT_FOUND'; end if;
  if v_pay.status = 'PAID' then return; end if;
  update public.payments set status = 'PAID' where id = v_pay.id;
  if v_pay.booking_id is not null then
    select * into v_book from public.bookings where id = v_pay.booking_id for update;
    if v_book is null
       or v_book.status <> 'PENDING_PAYMENT'
       or v_book.locked_until <= now() then
      update public.payments set status = 'REFUND_PENDING' where id = v_pay.id;
      return;
    end if;
    update public.bookings set paid_amount = v_pay.amount where id = v_book.id;
    v_book := public.transition_booking_status(v_book.id, 'AWAITING_CALL', 'apply_payment', null, jsonb_build_object('payment_id', v_pay.id));
    select phone into v_phone from public.users where id = v_book.user_id;
    if v_phone is not null and not exists (
      select 1 from public.event_outbox
      where handler_type = 'WHATSAPP'
        and (payload->>'booking_id' = v_book.id::text or payload->'params'->>'booking_id' = v_book.id::text)
        and payload->>'template_name' = 'booking_payment_received'
    ) then
      insert into public.event_outbox (handler_type, payload)
      values ('WHATSAPP', jsonb_build_object('phone', v_phone, 'template_name', 'booking_payment_received',
                                             'params', jsonb_build_object('booking_id', v_book.id, 'amount', v_pay.amount)));
    end if;
  end if;
end $$;

revoke all on function public.apply_payment(bigint) from public, anon, authenticated;
grant execute on function public.apply_payment(bigint) to service_role;

-- ---------------------------------------------------------------------------
-- 2. submit_event_booking: entity_uuid populated in audit_log
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_event_booking(
  p_event_type_id UUID,
  p_start_time TIMESTAMPTZ,
  p_extra_services JSONB DEFAULT '[]'::jsonb,
  p_notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_event_type public.event_types;
  v_end_time TIMESTAMPTZ;
  v_booking_id UUID;
  v_base_price BIGINT;
  v_extras_price BIGINT := 0;
  v_total_price BIGINT;
  v_elem JSONB;
  v_extra_id UUID;
  v_qty INT;
  v_extra public.extra_services;
  v_line_total BIGINT;
  v_phone TEXT;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING errcode = '28000';
  END IF;

  IF p_event_type_id IS NULL OR p_start_time IS NULL THEN
    RAISE EXCEPTION 'BAD_REQUEST';
  END IF;

  IF p_start_time <= now() THEN
    RAISE EXCEPTION 'BAD_REQUEST';
  END IF;

  -- Validate event type
  SELECT * INTO v_event_type
  FROM public.event_types
  WHERE id = p_event_type_id
    AND is_active = true
    AND deleted_at IS NULL
    AND tenant_id = public.tenant_id();

  IF v_event_type.id IS NULL THEN
    RAISE EXCEPTION 'BAD_REQUEST';
  END IF;

  v_base_price := v_event_type.base_price_piastres;
  v_end_time := p_start_time + (v_event_type.default_duration_minutes || ' minutes')::interval;

  -- Validate and calculate extra services
  IF p_extra_services IS NOT NULL AND jsonb_array_length(p_extra_services) > 0 THEN
    FOR v_elem IN SELECT * FROM jsonb_array_elements(p_extra_services)
    LOOP
      v_extra_id := (v_elem->>'extra_service_id')::uuid;
      v_qty := COALESCE((v_elem->>'quantity')::int, 1);

      IF v_extra_id IS NULL OR v_qty <= 0 THEN
        RAISE EXCEPTION 'BAD_REQUEST';
      END IF;

      -- Check if service is associated with this event type and active
      SELECT es.* INTO v_extra
      FROM public.extra_services es
      JOIN public.event_type_extra_services etes ON etes.extra_service_id = es.id
      WHERE es.id = v_extra_id
        AND etes.event_type_id = p_event_type_id
        AND es.is_active = true
        AND es.deleted_at IS NULL
        AND es.tenant_id = public.tenant_id();

      IF v_extra.id IS NULL THEN
        RAISE EXCEPTION 'BAD_REQUEST';
      END IF;

      IF NOT v_extra.is_quantity_based AND v_qty <> 1 THEN
        RAISE EXCEPTION 'BAD_REQUEST';
      END IF;

      IF v_extra.is_quantity_based AND v_qty > v_extra.max_quantity THEN
        RAISE EXCEPTION 'BAD_REQUEST';
      END IF;

      v_extras_price := v_extras_price + (v_extra.price_piastres * v_qty);
    END LOOP;
  END IF;

  v_total_price := v_base_price + v_extras_price;

  -- Insert event booking in SUBMITTED status
  INSERT INTO public.event_bookings (
    customer_id,
    event_type_id,
    assigned_venue_id,
    start_time,
    end_time,
    status,
    notes,
    base_price_piastres,
    extra_services_price_piastres,
    total_price_piastres,
    paid_amount_piastres,
    tenant_id
  ) VALUES (
    v_user,
    p_event_type_id,
    NULL,
    p_start_time,
    v_end_time,
    'SUBMITTED',
    p_notes,
    v_base_price,
    v_extras_price,
    v_total_price,
    0,
    public.tenant_id()
  ) RETURNING id INTO v_booking_id;

  -- Insert snapshot line items
  IF p_extra_services IS NOT NULL AND jsonb_array_length(p_extra_services) > 0 THEN
    FOR v_elem IN SELECT * FROM jsonb_array_elements(p_extra_services)
    LOOP
      v_extra_id := (v_elem->>'extra_service_id')::uuid;
      v_qty := COALESCE((v_elem->>'quantity')::int, 1);

      SELECT * INTO v_extra FROM public.extra_services WHERE id = v_extra_id;
      v_line_total := v_extra.price_piastres * v_qty;

      INSERT INTO public.booking_extra_services (
        booking_id,
        extra_service_id,
        unit_price_piastres,
        quantity,
        total_price_piastres,
        tenant_id
      ) VALUES (
        v_booking_id,
        v_extra_id,
        v_extra.price_piastres,
        v_qty,
        v_line_total,
        public.tenant_id()
      );
    END LOOP;
  END IF;

  -- Audit log
  INSERT INTO public.audit_log (user_id, action, entity_type, entity_id, entity_uuid, meta)
  VALUES (
    v_user,
    'submit_event_booking',
    'event_bookings',
    0, -- entity_id bigint fallback
    v_booking_id,
    jsonb_build_object(
      'event_booking_id', v_booking_id,
      'event_type_id', p_event_type_id,
      'total_price_piastres', v_total_price
    )
  );

  -- WhatsApp Notification Outbox
  SELECT phone INTO v_phone FROM public.users WHERE id = v_user;
  IF v_phone IS NOT NULL THEN
    INSERT INTO public.event_outbox (handler_type, payload, tenant_id)
    VALUES (
      'WHATSAPP',
      jsonb_build_object(
        'phone', v_phone,
        'template_name', 'event_booking_submitted',
        'params', jsonb_build_object(
          'booking_id', v_booking_id,
          'event_name', v_event_type.name_ar,
          'start_time', p_start_time
        )
      ),
      public.tenant_id()
    );
  END IF;

  RETURN v_booking_id;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_event_booking(UUID, TIMESTAMPTZ, JSONB, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_event_booking(UUID, TIMESTAMPTZ, JSONB, TEXT) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. admin_confirm_booking: entity_uuid populated in audit_log
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_confirm_booking(
  p_booking_id UUID,
  p_venue_id UUID,
  p_confirmed_start TIMESTAMPTZ DEFAULT NULL,
  p_confirmed_end TIMESTAMPTZ DEFAULT NULL,
  p_admin_note TEXT DEFAULT NULL
)
RETURNS public.event_bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_booking public.event_bookings;
  v_venue public.venues_resources;
  v_start TIMESTAMPTZ;
  v_end TIMESTAMPTZ;
  v_customer_phone TEXT;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING errcode = '28000';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;

  IF p_booking_id IS NULL OR p_venue_id IS NULL THEN
    RAISE EXCEPTION 'BAD_REQUEST';
  END IF;

  SELECT * INTO v_booking
  FROM public.event_bookings
  WHERE id = p_booking_id AND tenant_id = public.tenant_id()
  FOR UPDATE;

  IF v_booking.id IS NULL OR v_booking.status NOT IN ('SUBMITTED', 'AWAITING_CALL') THEN
    RAISE EXCEPTION 'BAD_REQUEST';
  END IF;

  SELECT * INTO v_venue
  FROM public.venues_resources
  WHERE id = p_venue_id AND is_active = true AND deleted_at IS NULL AND tenant_id = public.tenant_id();

  IF v_venue.id IS NULL THEN
    RAISE EXCEPTION 'BAD_REQUEST';
  END IF;

  v_start := COALESCE(p_confirmed_start, v_booking.start_time);
  v_end := COALESCE(p_confirmed_end, v_booking.end_time);

  IF v_end <= v_start THEN
    RAISE EXCEPTION 'BAD_REQUEST';
  END IF;

  -- Attempt update (GiST constraint no_overlapping_venue_events will trap conflicts)
  BEGIN
    UPDATE public.event_bookings
    SET assigned_venue_id = p_venue_id,
        start_time = v_start,
        end_time = v_end,
        status = 'CONFIRMED',
        notes = CASE
          WHEN p_admin_note IS NOT NULL AND length(trim(p_admin_note)) > 0
          THEN coalesce(notes || E'\n', '') || '[Admin]: ' || trim(p_admin_note)
          ELSE notes
        END,
        updated_at = now()
    WHERE id = p_booking_id
    RETURNING * INTO v_booking;
  EXCEPTION
    WHEN exclusion_violation THEN
      RAISE EXCEPTION 'VENUE_ALREADY_BOOKED' USING errcode = 'P0001';
  END;

  -- Audit log
  INSERT INTO public.audit_log (user_id, action, entity_type, entity_id, entity_uuid, meta)
  VALUES (
    v_user,
    'admin_confirm_booking',
    'event_bookings',
    0,
    p_booking_id,
    jsonb_build_object(
      'event_booking_id', p_booking_id,
      'assigned_venue_id', p_venue_id,
      'start_time', v_start,
      'end_time', v_end
    )
  );

  -- WhatsApp Notification Outbox
  SELECT phone INTO v_customer_phone FROM public.users WHERE id = v_booking.customer_id;
  IF v_customer_phone IS NOT NULL THEN
    INSERT INTO public.event_outbox (handler_type, payload, tenant_id)
    VALUES (
      'WHATSAPP',
      jsonb_build_object(
        'phone', v_customer_phone,
        'template_name', 'event_booking_confirmed',
        'params', jsonb_build_object(
          'booking_id', v_booking.id,
          'venue_name', v_venue.name_ar,
          'start_time', v_start,
          'total_price_piastres', v_booking.total_price_piastres
        )
      ),
      public.tenant_id()
    );
  END IF;

  RETURN v_booking;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_confirm_booking(UUID, UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_confirm_booking(UUID, UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. admin_reject_booking: entity_uuid populated in audit_log
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_reject_booking(
  p_booking_id UUID,
  p_rejection_reason TEXT
)
RETURNS public.event_bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_booking public.event_bookings;
  v_customer_phone TEXT;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING errcode = '28000';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;

  IF p_booking_id IS NULL OR p_rejection_reason IS NULL OR length(trim(p_rejection_reason)) = 0 THEN
    RAISE EXCEPTION 'BAD_REQUEST';
  END IF;

  SELECT * INTO v_booking
  FROM public.event_bookings
  WHERE id = p_booking_id AND tenant_id = public.tenant_id()
  FOR UPDATE;

  IF v_booking.id IS NULL OR v_booking.status IN ('CANCELLED', 'REJECTED', 'COMPLETED') THEN
    RAISE EXCEPTION 'BAD_REQUEST';
  END IF;

  UPDATE public.event_bookings
  SET status = 'REJECTED',
      rejection_reason = trim(p_rejection_reason),
      updated_at = now()
  WHERE id = p_booking_id
  RETURNING * INTO v_booking;

  -- Audit log
  INSERT INTO public.audit_log (user_id, action, entity_type, entity_id, entity_uuid, meta)
  VALUES (
    v_user,
    'admin_reject_booking',
    'event_bookings',
    0,
    p_booking_id,
    jsonb_build_object(
      'event_booking_id', p_booking_id,
      'rejection_reason', trim(p_rejection_reason)
    )
  );

  -- WhatsApp Notification Outbox
  SELECT phone INTO v_customer_phone FROM public.users WHERE id = v_booking.customer_id;
  IF v_customer_phone IS NOT NULL THEN
    INSERT INTO public.event_outbox (handler_type, payload, tenant_id)
    VALUES (
      'WHATSAPP',
      jsonb_build_object(
        'phone', v_customer_phone,
        'template_name', 'event_booking_rejected',
        'params', jsonb_build_object(
          'booking_id', v_booking.id,
          'reason', trim(p_rejection_reason)
        )
      ),
      public.tenant_id()
    );
  END IF;

  RETURN v_booking;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reject_booking(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_booking(UUID, TEXT) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. admin_quick_cash_collect: entity_uuid populated in audit_log
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_quick_cash_collect(
  p_booking_id UUID,
  p_amount_piastres BIGINT,
  p_collector_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_booking public.event_bookings;
  v_new_paid BIGINT;
  v_new_status public.event_booking_status;
  v_audit_id BIGINT;
  v_customer_phone TEXT;
  v_event_name TEXT;
BEGIN
  -- Authorization Guard
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING errcode = '28000';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;

  IF p_booking_id IS NULL OR p_amount_piastres IS NULL OR p_amount_piastres <= 0 THEN
    RAISE EXCEPTION 'BAD_REQUEST' USING errcode = 'P0001';
  END IF;

  -- Lock booking row
  SELECT * INTO v_booking
  FROM public.event_bookings
  WHERE id = p_booking_id AND tenant_id = public.tenant_id()
  FOR UPDATE;

  IF v_booking.id IS NULL OR v_booking.status IN ('CANCELLED', 'REJECTED') THEN
    RAISE EXCEPTION 'BAD_REQUEST' USING errcode = 'P0001';
  END IF;

  v_new_paid := COALESCE(v_booking.paid_amount_piastres, 0) + p_amount_piastres;
  
  -- Advance status to PAID if fully paid or marked paid
  IF v_new_paid >= v_booking.total_price_piastres THEN
    v_new_status := 'PAID';
  ELSE
    v_new_status := 'PENDING_PAYMENT';
  END IF;

  UPDATE public.event_bookings
  SET paid_amount_piastres = v_new_paid,
      status = v_new_status,
      updated_at = now()
  WHERE id = p_booking_id
  RETURNING * INTO v_booking;

  -- Insert immutable payment audit log
  INSERT INTO public.payment_audit_logs (
    booking_id,
    amount_piastres,
    method,
    recorded_by,
    action,
    notes,
    tenant_id
  ) VALUES (
    p_booking_id,
    p_amount_piastres,
    'CASH',
    v_user,
    'CASH_COLLECTED',
    COALESCE(p_collector_note, 'تحصيل نقدي فوري بالخزينة'),
    public.tenant_id()
  ) RETURNING id INTO v_audit_id;

  -- General Audit log
  INSERT INTO public.audit_log (user_id, action, entity_type, entity_id, entity_uuid, meta)
  VALUES (
    v_user,
    'admin_quick_cash_collect',
    'event_bookings',
    0,
    p_booking_id,
    jsonb_build_object(
      'event_booking_id', p_booking_id,
      'amount_piastres', p_amount_piastres,
      'total_paid', v_new_paid,
      'status', v_new_status,
      'collector_note', p_collector_note
    )
  );

  -- Retrieve event details for WhatsApp template
  SELECT name_ar INTO v_event_name FROM public.event_types WHERE id = v_booking.event_type_id;
  SELECT phone INTO v_customer_phone FROM public.users WHERE id = v_booking.customer_id;

  -- WhatsApp Notification Outbox
  IF v_customer_phone IS NOT NULL THEN
    INSERT INTO public.event_outbox (handler_type, payload, tenant_id)
    VALUES (
      'WHATSAPP',
      jsonb_build_object(
        'phone', v_customer_phone,
        'template_name', 'event_booking_payment_received',
        'params', jsonb_build_object(
          'booking_id', v_booking.id,
          'event_name', COALESCE(v_event_name, 'مناسبة كنسية'),
          'amount_paid_piastres', p_amount_piastres,
          'total_paid_piastres', v_new_paid,
          'remaining_piastres', GREATEST(0, v_booking.total_price_piastres - v_new_paid)
        )
      ),
      public.tenant_id()
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'audit_id', v_audit_id,
    'booking_id', p_booking_id,
    'amount_piastres', p_amount_piastres,
    'total_paid_piastres', v_new_paid,
    'status', v_new_status
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_quick_cash_collect(UUID, BIGINT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_quick_cash_collect(UUID, BIGINT, TEXT) TO authenticated, service_role;

commit;
