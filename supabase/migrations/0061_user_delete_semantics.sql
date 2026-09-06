-- 0061_user_delete_semantics.sql
-- Set explicit ON DELETE RESTRICT on foreign keys referencing public.users

-- 1. bookings.user_id
ALTER TABLE public.bookings
  DROP CONSTRAINT IF EXISTS bookings_user_id_fkey,
  ADD CONSTRAINT bookings_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;

-- 2. complaints.user_id
ALTER TABLE public.complaints
  DROP CONSTRAINT IF EXISTS complaints_user_id_fkey,
  ADD CONSTRAINT complaints_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;

-- 3. complaints.assigned_to
ALTER TABLE public.complaints
  DROP CONSTRAINT IF EXISTS complaints_assigned_to_fkey,
  ADD CONSTRAINT complaints_assigned_to_fkey
    FOREIGN KEY (assigned_to) REFERENCES public.users(id) ON DELETE RESTRICT;

-- 4. waiting_list.user_id
ALTER TABLE public.waiting_list
  DROP CONSTRAINT IF EXISTS waiting_list_user_id_fkey,
  ADD CONSTRAINT waiting_list_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;
