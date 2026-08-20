-- 0062_drop_video_privacy_enum.sql
-- Drop orphan video_privacy enum type left over from decommissioned video delivery feature

DROP TYPE IF EXISTS public.video_privacy;
