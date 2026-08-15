-- 0039: Comprehensive platform hardening and bug fixes

-- 1. Synchronize Role checks in RPCs to 'USER' and 'ADMIN'
CREATE OR REPLACE FUNCTION public.book_slot(
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
    v_role TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '28000'; END IF;
    SELECT role INTO v_role FROM public.users WHERE id = v_user;
    IF v_role NOT IN ('USER', 'ADMIN') THEN RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501'; END IF;

    -- Delegate to atomic execution
    RETURN public.fn_book_slot_atomic(p_slot_id, p_quantity, p_opt_in, p_idempotency_key);
END;
$$;

GRANT EXECUTE ON FUNCTION public.book_slot(BIGINT, INT, BOOLEAN, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.purchase_video(
    p_video_id BIGINT,
    p_idempotency_key UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_role TEXT;
    v_video RECORD;
    v_purchase_id BIGINT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '28000'; END IF;
    SELECT role INTO v_role FROM public.users WHERE id = v_user;
    IF v_role NOT IN ('USER', 'ADMIN') THEN RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501'; END IF;

    SELECT * INTO v_video FROM public.videos WHERE id = p_video_id;
    IF v_video.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0002'; END IF;

    INSERT INTO public.video_purchases (video_id, user_id, paid_amount, tenant_id)
    VALUES (p_video_id, v_user, v_video.price, public.tenant_id())
    ON CONFLICT (video_id, user_id) DO NOTHING
    RETURNING id INTO v_purchase_id;

    RETURN jsonb_build_object('success', true, 'purchase_id', coalesce(v_purchase_id, 0));
END;
$$;

GRANT EXECUTE ON FUNCTION public.purchase_video(BIGINT, UUID) TO authenticated;

-- 2. Automatic Capacity Restoration on Booking Cancellation/Expiry
CREATE OR REPLACE FUNCTION public.fn_restore_slot_capacity_on_cancel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF (OLD.status IN ('CONFIRMED', 'PENDING_PAYMENT', 'AWAITING_CALL') 
        AND NEW.status IN ('CANCELLED', 'EXPIRED', 'REFUNDED')) THEN
        
        UPDATE public.service_slots
        SET remaining_capacity = remaining_capacity + 1,
            updated_at = clock_timestamp()
        WHERE id = NEW.slot_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_restore_slot_capacity ON public.bookings;
CREATE TRIGGER tr_restore_slot_capacity
AFTER UPDATE OF status ON public.bookings
FOR EACH ROW
EXECUTE FUNCTION public.fn_restore_slot_capacity_on_cancel();

-- 3. Atomic Event Outbox Batch Claim RPC
CREATE OR REPLACE FUNCTION public.claim_event_outbox_batch(
    p_batch_size INT DEFAULT 100
)
RETURNS TABLE (
    id BIGINT,
    event_type TEXT,
    payload JSONB,
    retry_count INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    WITH claimed AS (
        SELECT eo.id
        FROM public.event_outbox eo
        WHERE eo.status = 'PENDING'
          AND eo.next_retry_at <= now()
        ORDER BY eo.created_at ASC
        LIMIT p_batch_size
        FOR UPDATE SKIP LOCKED
    )
    UPDATE public.event_outbox u
    SET status = 'PROCESSING',
        updated_at = now()
    FROM claimed
    WHERE u.id = claimed.id
    RETURNING u.id, u.event_type, u.payload, u.retry_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_event_outbox_batch(INT) TO service_role, authenticated, anon;
