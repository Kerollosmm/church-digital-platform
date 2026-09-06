-- Migration 0053: Backend Security and Correctness Fixes
-- Feature: 007-backend-security-fixes
-- Verified against live database and working tree 2026-08-17

-- ============================================================================
-- Section 1: User Story 1 - Tamper-Proof Financial & Audit Operations (P1)
-- ============================================================================

-- T011: Revoke direct client DML on sensitive tables (retain SELECT)
REVOKE INSERT, UPDATE, DELETE ON public.payments, public.complaints, public.audit_log, public.roles_permissions FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.users FROM anon, authenticated;

-- T012: Drop broad p0_admin_all and create targeted replacement SELECT policies
DROP POLICY IF EXISTS p0_admin_all ON public.payments;
DROP POLICY IF EXISTS payments_admin_select ON public.payments;
CREATE POLICY payments_admin_select ON public.payments
  FOR SELECT TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id());

DROP POLICY IF EXISTS p0_admin_all ON public.audit_log;
DROP POLICY IF EXISTS audit_log_admin_select ON public.audit_log;
CREATE POLICY audit_log_admin_select ON public.audit_log
  FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS p0_admin_all ON public.roles_permissions;
DROP POLICY IF EXISTS roles_permissions_admin_select ON public.roles_permissions;
CREATE POLICY roles_permissions_admin_select ON public.roles_permissions
  FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS p0_admin_all ON public.complaints;
-- complaints needs no replacement SELECT policy on table: 'complaints deny table access' (SELECT false)
-- is active and admin reads go through v_complaints view.

-- T013: Drop unreachable complaints_admin_assign policy and dead users mutation policies
DROP POLICY IF EXISTS complaints_admin_assign ON public.complaints;
DROP POLICY IF EXISTS p0_admin_update_users ON public.users;
DROP POLICY IF EXISTS p0_admin_insert_users ON public.users;
DROP POLICY IF EXISTS p0_admin_delete_users ON public.users;
-- NOTE: Complaint assignments and user mutations must proceed via dedicated SECURITY DEFINER RPCs.

-- T014: Restrict apply_payment(bigint) to service_role only
REVOKE ALL ON FUNCTION public.apply_payment(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_payment(bigint) TO service_role;

-- T015: Restrict maintenance / cron RPCs to service_role and postgres
REVOKE ALL ON FUNCTION public.expire_stale_bookings() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_stale_bookings() TO service_role, postgres;

REVOKE ALL ON FUNCTION public.promote_waiting_list(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.promote_waiting_list(bigint) TO service_role, postgres;

REVOKE ALL ON FUNCTION public.materialize_analytics() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.materialize_analytics() TO service_role, postgres;

-- T016: Restrict rbac_allows from PUBLIC and anon enumeration
REVOKE ALL ON FUNCTION public.rbac_allows(public.app_role, text, text) FROM PUBLIC, anon;

-- T017: Architectural Decision Note:
-- active_booking_count is read-only and preserved for v_available_slots.
-- decrypt_complaint, emergency_override, cancel_booking, confirm_booking,
-- complete_booking, join_waiting_list, manual_book internally verify caller roles/IDs.


-- ============================================================================
-- Section 2: User Story 2 - Accurate Slot Capacity Without Counter Drift (P1)
-- ============================================================================

-- T023: Drop restore slot capacity trigger and function
DROP TRIGGER IF EXISTS tr_restore_slot_capacity ON public.bookings;
DROP FUNCTION IF EXISTS public.fn_restore_slot_capacity_on_cancel();

-- T024: Drop slot depletion trigger and function
DROP TRIGGER IF EXISTS tr_on_slot_depletion ON public.service_slots;
DROP FUNCTION IF EXISTS public.fn_broadcast_slot_depletion();

-- T025: Drop old book_slot overloads and create consolidated canonical book_slot
DROP FUNCTION IF EXISTS public.book_slot(bigint, boolean);
DROP FUNCTION IF EXISTS public.book_slot(bigint, integer, boolean, uuid);
DROP FUNCTION IF EXISTS public.fn_book_slot_atomic(bigint, integer, boolean, uuid);

CREATE OR REPLACE FUNCTION public.book_slot(
  p_slot_id bigint,
  p_opt_in boolean DEFAULT false,
  p_idempotency_key uuid DEFAULT NULL
)
RETURNS public.bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_role text := public.current_user_role();
  v_slot public.service_slots;
  v_mine integer;
  v_active_count integer;
  v_booking public.bookings;
  v_user_phone text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '28000';
  END IF;

  v_role := public.current_user_role();
  IF v_role NOT IN ('USER', 'ADMIN', 'SUPER_ADMIN', 'PARISHIONER') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  -- Idempotency check
  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_booking
    FROM public.bookings
    WHERE notes = p_idempotency_key::text
      AND user_id = v_user_id;
    IF FOUND THEN
      RETURN v_booking;
    END IF;
  END IF;

  -- Lock slot row for concurrency control
  SELECT * INTO v_slot
  FROM public.service_slots
  WHERE id = p_slot_id AND deleted_at IS NULL
  FOR UPDATE;

  IF v_slot.id IS NULL THEN
    RAISE EXCEPTION 'SLOT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_slot.status = 'CLOSED' OR v_slot.starts_at <= now() THEN
    RAISE EXCEPTION 'SLOT_UNAVAILABLE' USING ERRCODE = 'P0001';
  END IF;

  -- Max 3 active bookings per user
  SELECT count(*) INTO v_mine
  FROM public.bookings
  WHERE user_id = v_user_id AND status IN ('PENDING_PAYMENT', 'AWAITING_CALL', 'CONFIRMED');
  IF v_mine >= 3 THEN
    RAISE EXCEPTION 'TOO_MANY_ACTIVE_BOOKINGS' USING ERRCODE = 'P0001';
  END IF;

  -- Duplicate booking check
  IF EXISTS (
    SELECT 1 FROM public.bookings
    WHERE slot_id = p_slot_id AND user_id = v_user_id
      AND status IN ('PENDING_PAYMENT', 'AWAITING_CALL', 'CONFIRMED')
  ) THEN
    RAISE EXCEPTION 'ALREADY_BOOKED_SLOT' USING ERRCODE = 'P0001';
  END IF;

  -- Compute active booking count dynamically
  v_active_count := public.active_booking_count(p_slot_id);
  IF v_active_count >= v_slot.capacity THEN
    RAISE EXCEPTION 'SLOT_FULL' USING ERRCODE = 'P0001';
  END IF;

  -- Handle WhatsApp opt-in
  IF p_opt_in THEN
    SELECT phone INTO v_user_phone FROM public.users WHERE id = v_user_id;
    IF v_user_phone IS NOT NULL THEN
      INSERT INTO public.whatsapp_optins (phone, source)
      VALUES (v_user_phone, 'BOOKING')
      ON CONFLICT (phone) DO UPDATE SET consented_at = now();
    END IF;
  END IF;

  -- Insert booking
  INSERT INTO public.bookings (
    tenant_id,
    slot_id,
    user_id,
    status,
    paid_amount,
    notes,
    locked_until,
    created_by
  ) VALUES (
    public.tenant_id(),
    p_slot_id,
    v_user_id,
    'PENDING_PAYMENT',
    COALESCE(v_slot.price, 0),
    p_idempotency_key::text,
    now() + interval '20 minutes',
    'system'
  )
  RETURNING * INTO v_booking;

  -- Audit log entry
  INSERT INTO public.audit_log (user_id, action, entity_type, entity_id, meta)
  VALUES (
    v_user_id,
    'book_slot',
    'bookings',
    v_booking.id,
    jsonb_build_object('slot_id', p_slot_id, 'opt_in', p_opt_in)
  );

  -- Emit SLOT_EXHAUSTED realtime signal if slot is now fully booked
  IF (v_active_count + 1) >= v_slot.capacity THEN
    PERFORM pg_notify(
      'realtime:event_inventory',
      jsonb_build_object(
        'topic', 'slot:' || p_slot_id::text || ':availability',
        'event', 'SLOT_EXHAUSTED',
        'payload', jsonb_build_object('slot_id', p_slot_id, 'status', 'BOOKED')
      )::text
    );
  END IF;

  RETURN v_booking;
END;
$$;

REVOKE ALL ON FUNCTION public.book_slot(bigint, boolean, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.book_slot(bigint, boolean, uuid) TO authenticated;

-- T026: manual_book verified and preserved (locks slot and checks active_booking_count)

-- T027: Drop remaining_capacity column from service_slots
ALTER TABLE public.service_slots DROP COLUMN IF EXISTS remaining_capacity;

-- T028: Add FOR UPDATE SKIP LOCKED to candidate selection in expire_stale_bookings
CREATE OR REPLACE FUNCTION public.expire_stale_bookings()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r record;
  n int := 0;
BEGIN
  FOR r IN
    SELECT id, slot_id
    FROM public.bookings
    WHERE status = 'PENDING_PAYMENT'
      AND locked_until < now()
    FOR UPDATE SKIP LOCKED
  LOOP
    PERFORM public.transition_booking_status(r.id, 'CANCELLED', 'expire_lock', 'stale payment lock', jsonb_build_object('slot_id', r.slot_id));
    PERFORM public.promote_waiting_list(r.slot_id);
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_stale_bookings() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_stale_bookings() TO service_role, postgres;


-- ============================================================================
-- Section 3: User Story 3 - Clean Pivot & Decommissioning of Video Machinery (P2)
-- ============================================================================

-- T032: Drop video tables, column, and RPCs
DROP TABLE IF EXISTS public.video_purchases CASCADE;
DROP TABLE IF EXISTS public.videos CASCADE;
ALTER TABLE public.payments DROP COLUMN IF EXISTS video_id;

DROP FUNCTION IF EXISTS public.purchase_video(bigint, uuid);
DROP FUNCTION IF EXISTS public.purchase_video(bigint);
DROP FUNCTION IF EXISTS public.apply_video_payment(bigint);
DROP FUNCTION IF EXISTS public.deliver_personal_video(text, text, text, bigint);

-- T033: Update event_outbox template check to drop video_ready
ALTER TABLE public.event_outbox
  DROP CONSTRAINT IF EXISTS event_outbox_whatsapp_template_check;

ALTER TABLE public.event_outbox
  ADD CONSTRAINT event_outbox_whatsapp_template_check
  CHECK (
    handler_type <> 'WHATSAPP'
    OR (payload->>'template_name') IN (
      'booking_confirmed',
      'payment_received',
      'booking_cancelled',
      'booking_rescheduled',
      'booking_apology',
      'otp_auth',
      'booking_payment_received',
      'booking_offer'
    )
  );

-- T034: Unschedule youtube-expiry pg_cron job
DO $$
DECLARE
  r record;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    FOR r IN SELECT jobid FROM cron.job WHERE jobname = 'youtube-expiry' OR command LIKE '%youtube-expiry%' LOOP
      PERFORM cron.unschedule(r.jobid);
    END LOOP;
  END IF;
END $$;



-- ============================================================================
-- Section 4: User Story 4 - Resilient Background Dispatch & Recovery (P2)
-- ============================================================================

-- T043: Add claimed_at and last_error columns to event_outbox
ALTER TABLE public.event_outbox
  ADD COLUMN IF NOT EXISTS claimed_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_error text;

-- T044: Update claim_event_outbox_batch with claimed_at and FOR UPDATE SKIP LOCKED
DROP FUNCTION IF EXISTS public.claim_event_outbox_batch(integer);
CREATE OR REPLACE FUNCTION public.claim_event_outbox_batch(p_batch_size integer)
RETURNS SETOF public.event_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  WITH to_claim AS (
    SELECT id
    FROM public.event_outbox
    WHERE status = 'PENDING'
      AND (next_attempt_at IS NULL OR next_attempt_at <= now())
    ORDER BY created_at ASC
    LIMIT p_batch_size
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.event_outbox o
  SET status = 'PROCESSING',
      claimed_at = now()
  FROM to_claim tc
  WHERE o.id = tc.id
  RETURNING o.*;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_event_outbox_batch(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_event_outbox_batch(integer) TO service_role, postgres;

-- T045: Create reap_stuck_outbox_events function
DROP FUNCTION IF EXISTS public.reap_stuck_outbox_events(integer);
DROP FUNCTION IF EXISTS public.reap_stuck_outbox_events(interval);

CREATE OR REPLACE FUNCTION public.reap_stuck_outbox_events(p_timeout interval DEFAULT interval '5 minutes')
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_c1 integer := 0;
  v_c2 integer := 0;
BEGIN
  -- Branch 1: attempts < 5 -> reset to PENDING, increment attempts, set last_error
  WITH candidates_pending AS (
    SELECT id
    FROM public.event_outbox
    WHERE status = 'PROCESSING'
      AND claimed_at < now() - p_timeout
      AND attempts < 5
    FOR UPDATE SKIP LOCKED
  ),
  reaped_pending AS (
    UPDATE public.event_outbox o
    SET status = 'PENDING',
        attempts = o.attempts + 1,
        next_attempt_at = now(),
        claimed_at = NULL,
        last_error = 'stuck processing reaped'
    FROM candidates_pending c
    WHERE o.id = c.id
    RETURNING o.id
  )
  SELECT count(*)::integer INTO v_c1 FROM reaped_pending;

  -- Branch 2: attempts >= 5 -> transition to FAILED, set last_error
  WITH candidates_failed AS (
    SELECT id
    FROM public.event_outbox
    WHERE status = 'PROCESSING'
      AND claimed_at < now() - p_timeout
      AND attempts >= 5
    FOR UPDATE SKIP LOCKED
  ),
  reaped_failed AS (
    UPDATE public.event_outbox o
    SET status = 'FAILED',
        claimed_at = NULL,
        last_error = 'stuck processing reaped at max attempts'
    FROM candidates_failed cf
    WHERE o.id = cf.id
    RETURNING o.id
  )
  SELECT count(*)::integer INTO v_c2 FROM reaped_failed;

  RETURN v_c1 + v_c2;
END;
$$;

REVOKE ALL ON FUNCTION public.reap_stuck_outbox_events(interval) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reap_stuck_outbox_events(interval) TO service_role, postgres;

-- T046: Schedule reap_stuck_outbox_events on pg_cron every 5 minutes
DO $$
DECLARE
  r record;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    FOR r IN SELECT jobid FROM cron.job WHERE jobname = 'reap-stuck-outbox-events' OR command LIKE '%reap_stuck_outbox_events%' LOOP
      PERFORM cron.unschedule(r.jobid);
    END LOOP;
    PERFORM cron.schedule('reap-stuck-outbox-events', '*/5 * * * *', 'SELECT public.reap_stuck_outbox_events();');
  END IF;
END $$;

-- T047: Create v_failed_outbox_events view with security_invoker
CREATE OR REPLACE VIEW public.v_failed_outbox_events
WITH (security_invoker = true)
AS
SELECT
  id,
  tenant_id,
  handler_type,
  payload,
  status,
  attempts,
  last_error,
  next_attempt_at,
  claimed_at,
  payload->>'template_name' AS template_name,
  payload->>'phone' AS recipient_phone,
  created_at
FROM public.event_outbox
WHERE status = 'FAILED'
  AND tenant_id = public.tenant_id();

DROP POLICY IF EXISTS "event_outbox_admin_select" ON public.event_outbox;
CREATE POLICY "event_outbox_admin_select"
  ON public.event_outbox
  FOR SELECT
  TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id());

GRANT SELECT ON public.event_outbox TO authenticated;
GRANT SELECT ON public.v_failed_outbox_events TO authenticated;

-- T048: Create admin_resend_outbox_event RPC
DROP FUNCTION IF EXISTS public.admin_resend_outbox_event(bigint);

CREATE OR REPLACE FUNCTION public.admin_resend_outbox_event(p_event_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  UPDATE public.event_outbox
  SET status = 'PENDING',
      attempts = 0,
      last_error = NULL,
      claimed_at = NULL,
      next_attempt_at = now()
  WHERE id = p_event_id
    AND tenant_id = public.tenant_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  RETURN jsonb_build_object('success', true, 'event_id', p_event_id, 'status', 'PENDING');
END;
$$;

REVOKE ALL ON FUNCTION public.admin_resend_outbox_event(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resend_outbox_event(bigint) TO authenticated;



-- ============================================================================
-- Section 5: User Story 5 - Explicit Administrative Roles & Hierarchy (P3)
-- ============================================================================

-- T053: Redefine is_super_admin() to check role = 'SUPER_ADMIN'::public.app_role
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = auth.uid()
      AND role = 'SUPER_ADMIN'::public.app_role
  );
$$;

REVOKE ALL ON FUNCTION public.is_super_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;



-- ============================================================================
-- Section 6: Polish & Cross-Cutting Fixes (Storage / FAQ / Backlog / Social Links)
-- ============================================================================

-- T063: Fix v_content_backlog view and forward-migrate get_backlog
DROP FUNCTION IF EXISTS public.get_backlog(timestamptz, bigint, int);
DROP VIEW IF EXISTS public.v_content_backlog CASCADE;

CREATE OR REPLACE VIEW public.v_content_backlog AS
SELECT
  'missing_alt_text'::text AS kind,
  p.created_at AS source_created_at,
  ('priest:' || p.id)::text AS id,
  ('priest:' || p.name)::text AS label
FROM public.priests p
WHERE p.photo_url IS NOT NULL
  AND p.photo_url !~ '^https?://'
  AND NOT EXISTS (
    SELECT 1 FROM storage.objects so
    WHERE so.bucket_id = 'priest_photos'
      AND so.name = p.photo_url
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.media_assets m
    WHERE m.bucket = 'priest_photos'
      AND m.storage_path = p.photo_url
  )
UNION ALL
SELECT
  'missing_alt_text'::text AS kind,
  so.created_at AS source_created_at,
  ('object:' || so.id)::text AS id,
  (so.bucket_id || '/' || so.name)::text AS label
FROM storage.objects so
WHERE so.bucket_id IN ('priest_photos', 'church_media', 'announcement_images')
  AND NOT EXISTS (
    SELECT 1 FROM public.media_assets m
    WHERE m.bucket = so.bucket_id
      AND m.storage_path = so.name
  );

REVOKE ALL ON public.v_content_backlog FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.v_content_backlog TO service_role;

CREATE OR REPLACE FUNCTION public.get_backlog(
  p_before_created_at timestamptz DEFAULT NULL,
  p_after_id text DEFAULT NULL,
  p_limit int DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_limit int;
  v_items jsonb := '[]'::jsonb;
  v_next_cursor jsonb := null;
  v_last_created_at timestamptz;
  v_last_id text;
  v_count int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  v_limit := LEAST(COALESCE(p_limit, 50), 100);
  IF v_limit <= 0 THEN
    v_limit := 50;
  END IF;

  WITH filtered AS (
    SELECT kind, source_created_at, id, label
    FROM public.v_content_backlog
    WHERE (
      p_before_created_at IS NULL
      OR source_created_at < p_before_created_at
      OR (source_created_at = p_before_created_at AND id < p_after_id)
    )
    ORDER BY source_created_at DESC, id DESC
    LIMIT v_limit
  )
  SELECT
    COALESCE(jsonb_agg(to_jsonb(f)), '[]'::jsonb),
    count(*),
    (ARRAY_AGG(f.source_created_at ORDER BY f.source_created_at DESC, f.id DESC))[count(*)],
    (ARRAY_AGG(f.id ORDER BY f.source_created_at DESC, f.id DESC))[count(*)]
  INTO v_items, v_count, v_last_created_at, v_last_id
  FROM filtered f;

  IF v_count = v_limit AND v_last_created_at IS NOT NULL AND v_last_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.v_content_backlog
      WHERE source_created_at < v_last_created_at
         OR (source_created_at = v_last_created_at AND id < v_last_id)
    ) THEN
      v_next_cursor := jsonb_build_object(
        'created_at', to_char(v_last_created_at, 'YYYY-MM-DD"T"HH24:MI:SS.USOF'),
        'id', v_last_id
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'items', v_items,
    'next_cursor', v_next_cursor
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_backlog(timestamptz, text, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_backlog(timestamptz, text, int) TO authenticated, service_role;

-- Forward-migrate social_links grant hardening
REVOKE ALL ON public.social_links FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.social_links TO authenticated;

-- T064: Forward-migrate faq_categories hardening
ALTER TABLE public.faq_categories
  ALTER COLUMN tenant_id SET DEFAULT public.tenant_id();

DROP POLICY IF EXISTS "faq_categories_admin_all" ON public.faq_categories;
DROP POLICY IF EXISTS "p0_admin_all" ON public.faq_categories;
DROP POLICY IF EXISTS "faq_categories_admin_manage" ON public.faq_categories;
DROP POLICY IF EXISTS "faq_categories_public_read" ON public.faq_categories;

CREATE POLICY "faq_categories_admin_manage"
  ON public.faq_categories
  FOR ALL
  TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

CREATE POLICY "faq_categories_public_read"
  ON public.faq_categories
  FOR SELECT
  TO anon, authenticated
  USING (published = true AND tenant_id = public.tenant_id());

REVOKE ALL ON public.faq_categories FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.faq_categories TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.faq_categories TO authenticated;

-- T064: Forward-migrate storage.objects policies
DO $$
BEGIN
  ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
EXCEPTION
  WHEN insufficient_privilege THEN NULL;
END $$;

-- priest_photos
DROP POLICY IF EXISTS "Admins can upload priest photos" ON storage.objects;
CREATE POLICY "Admins can upload priest photos"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'priest_photos' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can update priest photos" ON storage.objects;
CREATE POLICY "Admins can update priest photos"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'priest_photos' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can delete priest photos" ON storage.objects;
CREATE POLICY "Admins can delete priest photos"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'priest_photos' AND public.is_admin());

DROP POLICY IF EXISTS "Users can read priest photos" ON storage.objects;
CREATE POLICY "Users can read priest photos"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'priest_photos');

-- church_media
DROP POLICY IF EXISTS "Admins can upload church media" ON storage.objects;
CREATE POLICY "Admins can upload church media"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'church_media' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can update church media" ON storage.objects;
CREATE POLICY "Admins can update church media"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'church_media' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can delete church media" ON storage.objects;
CREATE POLICY "Admins can delete church media"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'church_media' AND public.is_admin());

DROP POLICY IF EXISTS "Users can read church media" ON storage.objects;
CREATE POLICY "Users can read church media"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'church_media');

-- announcement_images
DROP POLICY IF EXISTS "Admins can upload announcement images" ON storage.objects;
CREATE POLICY "Admins can upload announcement images"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'announcement_images' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can update announcement images" ON storage.objects;
CREATE POLICY "Admins can update announcement images"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'announcement_images' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can delete announcement images" ON storage.objects;
CREATE POLICY "Admins can delete announcement images"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'announcement_images' AND public.is_admin());

DROP POLICY IF EXISTS "Users can read announcement images" ON storage.objects;
CREATE POLICY "Users can read announcement images"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'announcement_images');

GRANT SELECT ON storage.buckets TO authenticated, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON storage.objects TO authenticated;



