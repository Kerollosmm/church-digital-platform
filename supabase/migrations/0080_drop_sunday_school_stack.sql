-- ==============================================================================
-- 0080_drop_sunday_school_stack.sql
-- Decommission Sunday School and attendance management stack per product owner
-- ==============================================================================

-- 1. Drop Stored Procedures & Functions
DROP FUNCTION IF EXISTS public.get_class_visitation_list(UUID, DATE);
DROP FUNCTION IF EXISTS public.record_bulk_attendance(UUID, DATE, JSONB, TEXT);
DROP FUNCTION IF EXISTS public.is_class_servant(UUID);

-- 2. Drop Tables (in dependency order)
DROP TABLE IF EXISTS public.sunday_school_attendance CASCADE;
DROP TABLE IF EXISTS public.sunday_school_sessions CASCADE;
DROP TABLE IF EXISTS public.sunday_school_students CASCADE;
DROP TABLE IF EXISTS public.sunday_school_servants CASCADE;
DROP TABLE IF EXISTS public.sunday_school_classes CASCADE;
