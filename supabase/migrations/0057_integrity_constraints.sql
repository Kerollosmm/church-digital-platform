-- 0057_integrity_constraints.sql
-- Add domain integrity CHECK constraints and drop redundant booking_status check

-- 1. service_slots: ends_at > starts_at, capacity >= 0, price >= 0
ALTER TABLE public.service_slots
  ADD CONSTRAINT service_slots_time_order_chk CHECK (ends_at > starts_at),
  ADD CONSTRAINT service_slots_capacity_nonneg_chk CHECK (capacity >= 0),
  ADD CONSTRAINT service_slots_price_nonneg_chk CHECK (price >= 0);

-- 2. bookings: seat_count >= 1 and drop redundant status check
ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_seat_count_min_chk CHECK (seat_count >= 1),
  DROP CONSTRAINT IF EXISTS bookings_status_check;

-- 3. payments: amount >= 0
ALTER TABLE public.payments
  ADD CONSTRAINT payments_amount_nonneg_chk CHECK (amount >= 0);

-- 4. media_assets: polymorphic pair both null or both non-null
ALTER TABLE public.media_assets
  ADD CONSTRAINT media_assets_polymorphic_chk CHECK ((content_type IS NULL) = (content_id IS NULL));
