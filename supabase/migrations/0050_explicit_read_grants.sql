-- ==============================================================================
-- 0050_explicit_read_grants.sql
-- Purpose: Explicit table, view, and sequence grants for anon and authenticated
--          roles aligned with RLS policies, removing implicit reliance on default ACLs.
-- ==============================================================================

-- ==============================================================================
-- 1. Public catalog and public-read tables
-- ==============================================================================
GRANT SELECT ON public.announcements TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.announcements TO authenticated;

GRANT SELECT ON public.faq TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.faq TO authenticated;

GRANT SELECT ON public.faq_categories TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.faq_categories TO authenticated;

GRANT SELECT ON public.priests TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.priests TO authenticated;

GRANT SELECT ON public.service_slots TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.service_slots TO authenticated;

GRANT SELECT ON public.services TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.services TO authenticated;

GRANT SELECT ON public.social_links TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.social_links TO authenticated;

GRANT SELECT ON public.videos TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.videos TO authenticated;

GRANT SELECT ON public.video_purchases TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.video_purchases TO authenticated;

GRANT SELECT ON public.bookings TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.bookings TO authenticated;

GRANT SELECT ON public.slot_utilization_monthly TO anon, authenticated;
GRANT SELECT ON public.payments_monthly TO anon, authenticated;
GRANT SELECT ON public.bookings_monthly TO anon, authenticated;

-- ==============================================================================
-- 2. Authenticated-only tables (SELECT and/or DML to authenticated)
-- ==============================================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON public.users TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.complaints TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.waiting_list TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.whatsapp_optins TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.roles_permissions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.offline_sync_log TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.audit_log TO authenticated;


-- ==============================================================================
-- 3. Public and authenticated views
-- ==============================================================================
GRANT SELECT ON public.v_services TO anon, authenticated;
GRANT SELECT ON public.v_priests TO anon, authenticated;
GRANT SELECT ON public.v_faq TO anon, authenticated;
GRANT SELECT ON public.v_schedule_today TO anon, authenticated;
GRANT SELECT ON public.v_available_slots TO anon, authenticated;
GRANT SELECT ON public.v_my_videos TO anon, authenticated;
GRANT SELECT ON public.v_my_bookings TO anon, authenticated;
GRANT SELECT ON public.v_analytics_utilization TO anon, authenticated;
GRANT SELECT ON public.v_analytics_payments TO anon, authenticated;
GRANT SELECT ON public.v_analytics_bookings TO anon, authenticated;

-- ==============================================================================
-- 4. Identity sequences for client-accessible tables
-- ==============================================================================
GRANT USAGE, SELECT ON SEQUENCE public.announcements_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.bookings_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.complaints_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.faq_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.faq_categories_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.payments_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.priests_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.roles_permissions_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.service_slots_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.services_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.social_links_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.video_purchases_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.videos_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.waiting_list_id_seq TO authenticated;
