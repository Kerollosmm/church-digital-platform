-- ==============================================================================
-- 0072_security_hardening.sql
-- Security hardening:
--   1) publish_announcement: harden storage object LIKE pattern matching with format()
--   2) Explicit revoke/grant enforcement on publish_announcement
-- Forward-only: applied migrations are never modified.
-- ==============================================================================

create or replace function public.publish_announcement(p_id bigint)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ann public.announcements;
  v_has_images boolean := false;
  v_linked_count int := 0;
  v_invalid_count int := 0;
  v_pat_prefix text;
  v_pat_direct text;
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select * into v_ann from public.announcements where id = p_id;
  if v_ann is null then
    raise exception 'ANNOUNCEMENT_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_pat_prefix := format('ann%s/%%', p_id);
  v_pat_direct := format('%s/%%', p_id);

  -- Check if announcement body or storage contains images
  if v_ann.body_ar like '%announcement_images%'
     or exists (
       select 1 from storage.objects
       where bucket_id = 'announcement_images'
         and (name like v_pat_prefix or name like v_pat_direct)
     )
  then
    v_has_images := true;
  end if;

  select count(*) into v_linked_count
  from public.media_assets
  where content_type = 'announcement' and content_id = p_id;

  if v_has_images and v_linked_count = 0 then
    raise exception 'ALT_TEXT_REQUIRED' using errcode = 'P0001';
  end if;

  select count(*) into v_invalid_count
  from public.media_assets
  where content_type = 'announcement' and content_id = p_id
    and is_decorative = false
    and (alt_text_ar is null or length(trim(alt_text_ar)) = 0);

  if v_invalid_count > 0 then
    raise exception 'ALT_TEXT_REQUIRED' using errcode = 'P0001';
  end if;

  update public.announcements
  set published_at = now(),
      updated_at = now()
  where id = p_id;
end;
$$;

revoke all on function public.publish_announcement(bigint) from public, anon, authenticated;
grant execute on function public.publish_announcement(bigint) to authenticated, service_role;
