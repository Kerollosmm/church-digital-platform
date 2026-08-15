# Data Model & Schema Migration Specification

## Migration: `0035_concurrency_hardening.sql`

```sql
-- 1. Invariant capacity bound & schedule range
ALTER TABLE public.service_slots 
  ADD COLUMN IF NOT EXISTS remaining_capacity INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS schedule_range TSTZRANGE;

UPDATE public.service_slots 
SET remaining_capacity = GREATEST(capacity - public.active_booking_count(id), 0),
    schedule_range = tstzrange(starts_at, ends_at, '[)')
WHERE schedule_range IS NULL;

ALTER TABLE public.service_slots
  ADD CONSTRAINT check_remaining_capacity_non_negative CHECK (remaining_capacity >= 0),
  ADD CONSTRAINT check_schedule_valid CHECK (lower(schedule_range) < upper(schedule_range));

-- 2. Prevent overlapping altar/hall schedules
CREATE EXTENSION IF NOT EXISTS "btree_gist";

ALTER TABLE public.service_slots
ADD CONSTRAINT no_location_schedule_overlap
EXCLUDE USING GIST (
    location WITH =,
    schedule_range WITH &&
) WHERE (status <> 'CLOSED');

-- 3. Atomic Reservation RPC
CREATE OR REPLACE FUNCTION public.fn_book_slot_atomic(
    p_slot_id BIGINT,
    p_quantity INT DEFAULT 1,
    p_opt_in BOOLEAN DEFAULT FALSE,
    p_idempotency_key UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_slot RECORD;
    v_booking_id BIGINT;
    v_phone TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '28000'; END IF;
    IF p_quantity <= 0 OR p_quantity > 4 THEN RAISE EXCEPTION 'INVALID_QUANTITY' USING ERRCODE = '22023'; END IF;

    -- Idempotency check
    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_booking_id FROM public.bookings WHERE notes = p_idempotency_key::text;
        IF FOUND THEN
            RETURN jsonb_build_object('success', true, 'idempotent_replay', true, 'booking_id', v_booking_id);
        END IF;
    END IF;

    -- Atomic decrement (<100µs row lock)
    UPDATE public.service_slots
    SET remaining_capacity = remaining_capacity - p_quantity,
        updated_at = clock_timestamp()
    WHERE id = p_slot_id 
      AND status <> 'CLOSED' 
      AND starts_at > now()
      AND remaining_capacity >= p_quantity
    RETURNING id, price, remaining_capacity INTO v_slot;

    IF v_slot.id IS NULL THEN
        RAISE EXCEPTION 'INVENTORY_EXHAUSTED' USING ERRCODE = 'P0001';
    END IF;

    -- Create booking in single transaction
    INSERT INTO public.bookings (
        slot_id, user_id, status, paid_amount, locked_until, created_by, notes, tenant_id
    ) VALUES (
        p_slot_id, v_user, 'PENDING_PAYMENT', v_slot.price * p_quantity,
        now() + interval '20 minutes', 'system', p_idempotency_key::text, public.tenant_id()
    ) RETURNING id INTO v_booking_id;

    -- WhatsApp opt-in capture
    IF p_opt_in THEN
        SELECT phone INTO v_phone FROM public.users WHERE id = v_user;
        IF v_phone IS NOT NULL THEN
            INSERT INTO public.whatsapp_optins (phone, source) VALUES (v_phone, 'BOOKING')
            ON CONFLICT (phone) DO UPDATE SET consented_at = now();
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'booking_id', v_booking_id,
        'remaining_capacity', v_slot.remaining_capacity
    );
END;
$$;

-- 4. RLS InitPlan Scalar Subquery Optimizations
DROP POLICY IF EXISTS p0_bookings_read_own ON public.bookings;
CREATE POLICY p0_bookings_read_own ON public.bookings
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- 5. Realtime Depletion Broadcast Trigger
CREATE OR REPLACE FUNCTION public.fn_broadcast_slot_depletion()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public, pg_temp 
AS $$
BEGIN
    IF (OLD.remaining_capacity > 0 AND NEW.remaining_capacity = 0) THEN
        PERFORM pg_notify(
            'realtime:event_inventory',
            jsonb_build_object(
                'topic', 'slot:' || NEW.id::text || ':availability',
                'event', 'SLOT_EXHAUSTED',
                'payload', jsonb_build_object('slot_id', NEW.id, 'status', 'BOOKED')
            )::text
        );
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER tr_on_slot_depletion
AFTER UPDATE OF remaining_capacity ON public.service_slots
FOR EACH ROW WHEN (NEW.remaining_capacity = 0)
EXECUTE FUNCTION public.fn_broadcast_slot_depletion();
```