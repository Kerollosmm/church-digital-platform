-- =====================================================
-- Migration: 0047_database_optimizations_and_indexes.sql
-- Purpose: Multi-seat restore, foreign key indexes, partial indexes, and RLS InitPlan optimizations
-- Phase: Database Performance & Integrity
-- Date: 2026-08-16
-- =====================================================

-- 1. Add seat_count column to bookings if missing
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS seat_count INT NOT NULL DEFAULT 1;

-- 2. Fix multi-seat capacity restoration trigger
CREATE OR REPLACE FUNCTION public.fn_restore_slot_capacity_on_cancel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF (OLD.status IN ('CONFIRMED', 'PENDING_PAYMENT', 'AWAITING_CALL') 
        AND NEW.status = 'CANCELLED') THEN
        
        UPDATE public.service_slots
        SET remaining_capacity = remaining_capacity + coalesce(NEW.seat_count, 1),
            updated_at = clock_timestamp()
        WHERE id = NEW.slot_id;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_restore_slot_capacity_on_cancel() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tr_restore_slot_capacity ON public.bookings;
CREATE TRIGGER tr_restore_slot_capacity
AFTER UPDATE OF status ON public.bookings
FOR EACH ROW
EXECUTE FUNCTION public.fn_restore_slot_capacity_on_cancel();

-- 3. Foreign Key B-Tree Index Coverage
CREATE INDEX IF NOT EXISTS idx_service_slots_service_id ON public.service_slots(service_id);
CREATE INDEX IF NOT EXISTS idx_bookings_slot_id ON public.bookings(slot_id);
CREATE INDEX IF NOT EXISTS idx_bookings_user_id ON public.bookings(user_id);
CREATE INDEX IF NOT EXISTS idx_payments_booking_id ON public.payments(booking_id);
CREATE INDEX IF NOT EXISTS idx_payments_video_id ON public.payments(video_id);
CREATE INDEX IF NOT EXISTS idx_waiting_list_slot_id ON public.waiting_list(slot_id);
CREATE INDEX IF NOT EXISTS idx_waiting_list_user_id ON public.waiting_list(user_id);
CREATE INDEX IF NOT EXISTS idx_video_purchases_video_id ON public.video_purchases(video_id);
CREATE INDEX IF NOT EXISTS idx_video_purchases_user_id ON public.video_purchases(user_id);
CREATE INDEX IF NOT EXISTS idx_video_purchases_payment_id ON public.video_purchases(payment_id);
CREATE INDEX IF NOT EXISTS idx_complaints_user_id ON public.complaints(user_id);
CREATE INDEX IF NOT EXISTS idx_complaints_assigned_to ON public.complaints(assigned_to);

-- 4. Partial Indexes for Cron Jobs & Active Booking Lookups
CREATE INDEX IF NOT EXISTS idx_bookings_pending_lock
  ON public.bookings (locked_until)
  WHERE status = 'PENDING_PAYMENT';

CREATE INDEX IF NOT EXISTS idx_bookings_active_slot
  ON public.bookings (slot_id, status, locked_until)
  WHERE status IN ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED');

-- 5. RLS InitPlan Optimization ((SELECT auth.uid()))
DROP POLICY IF EXISTS "p0_users_read_own" ON public.users;
CREATE POLICY "p0_users_read_own" ON public.users
  FOR SELECT TO authenticated
  USING (id = (SELECT auth.uid()));

-- 6. Analytics Multi-Tenant Columns
ALTER TABLE public.slot_utilization_monthly ADD COLUMN IF NOT EXISTS tenant_id BIGINT NOT NULL DEFAULT public.tenant_id();
ALTER TABLE public.payments_monthly ADD COLUMN IF NOT EXISTS tenant_id BIGINT NOT NULL DEFAULT public.tenant_id();
ALTER TABLE public.bookings_monthly ADD COLUMN IF NOT EXISTS tenant_id BIGINT NOT NULL DEFAULT public.tenant_id();

-- 7. Realtime Publication Clean Up (Remove bookings table)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime DROP TABLE public.bookings;
EXCEPTION
  WHEN undefined_object THEN NULL;
  WHEN object_not_in_prerequisite_state THEN NULL;
END $$;
