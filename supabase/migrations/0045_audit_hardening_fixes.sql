-- =====================================================
-- Migration: 0045_audit_hardening_fixes.sql
-- Purpose: Schema alignment & RPC hardening (FR-009)
-- Phase: Feature 003 — Shared Kernel
-- Date: 2026-08-16
-- =====================================================

-- 1. Fix claim_event_outbox_batch signature & query (matches public.event_outbox exactly)
DROP FUNCTION IF EXISTS public.claim_event_outbox_batch(INT);
CREATE OR REPLACE FUNCTION public.claim_event_outbox_batch(
    p_batch_size INT DEFAULT 100
)
RETURNS TABLE (
    id BIGINT,
    handler_type public.event_handler_type,
    payload JSONB,
    attempts INT
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
          AND eo.next_attempt_at <= now()
        ORDER BY eo.created_at ASC
        LIMIT p_batch_size
        FOR UPDATE SKIP LOCKED
    )
    UPDATE public.event_outbox u
    SET status = 'PROCESSING'
    FROM claimed
    WHERE u.id = claimed.id
    RETURNING u.id, u.handler_type, u.payload, u.attempts;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_event_outbox_batch(INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_event_outbox_batch(INT) TO service_role;

-- 2. Add unique constraint on video_purchases and fix purchase_video RPC
ALTER TABLE public.video_purchases 
  DROP CONSTRAINT IF EXISTS uq_video_purchases_user_video;
ALTER TABLE public.video_purchases 
  ADD CONSTRAINT uq_video_purchases_user_video UNIQUE (video_id, user_id);

DROP FUNCTION IF EXISTS public.purchase_video(BIGINT);
DROP FUNCTION IF EXISTS public.purchase_video(BIGINT, UUID);

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
    v_payment_id BIGINT;
    v_purchase_id BIGINT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '28000'; END IF;
    SELECT role INTO v_role FROM public.users WHERE id = v_user;
    IF v_role IS NULL OR v_role NOT IN ('USER', 'ADMIN') THEN RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501'; END IF;

    SELECT * INTO v_video FROM public.videos WHERE id = p_video_id;
    IF v_video.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0002'; END IF;

    -- Create or get pending payment record
    INSERT INTO public.payments (video_id, amount, status, tenant_id)
    VALUES (p_video_id, v_video.price, 'PENDING', public.tenant_id())
    RETURNING id INTO v_payment_id;

    INSERT INTO public.video_purchases (video_id, user_id, payment_id, tenant_id)
    VALUES (p_video_id, v_user, v_payment_id, public.tenant_id())
    ON CONFLICT (video_id, user_id) DO NOTHING
    RETURNING id INTO v_purchase_id;

    RETURN jsonb_build_object(
        'success', true, 
        'purchase_id', coalesce(v_purchase_id, 0),
        'payment_id', v_payment_id
    );
END;
$$;

REVOKE ALL ON FUNCTION public.purchase_video(BIGINT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purchase_video(BIGINT, UUID) TO authenticated;

-- 3. video_purchases RLS tenant isolation & grants
DROP POLICY IF EXISTS "video_purchases own read" ON public.video_purchases;
DROP POLICY IF EXISTS "p0_video_purchases_own_read" ON public.video_purchases;
CREATE POLICY "p0_video_purchases_own_read" ON public.video_purchases
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) AND tenant_id = public.tenant_id());

GRANT SELECT ON public.video_purchases TO authenticated;
