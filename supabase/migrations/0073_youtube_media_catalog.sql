-- 0073: YouTube media catalog — free-content automation (church masses/sermons/livestreams)
-- Replaces the decommissioned paid-video machinery (ADR 0002) with a free,
-- read-only catalog synced from the church's public YouTube channel by the
-- `youtube-sync` Edge Function (YouTube Data API v3). No payments, no access
-- gating — parishioners simply browse the synced sermons/masses.
--
-- Architecture (per conventions.md):
--   * All writes happen through the SECURITY DEFINER `sync_youtube_videos` RPC.
--   * The Edge Function only touches the outside world (YouTube API) and calls
--     the RPC — it never writes `youtube_videos` directly.
--   * RLS: anon + authenticated read of available rows within the tenant;
--     admin write. tenant_id default + invariant enforced on every policy.

-- 1. youtube_videos table ---------------------------------------------------
create table if not exists public.youtube_videos (
  id bigint generated always as identity primary key,
  yt_video_id text not null,
  title text not null,
  description text,
  thumbnail_url text,
  yt_url text not null,
  published_at timestamptz,
  duration_seconds int,
  is_available boolean not null default true,
  synced_at timestamptz not null default now(),
  tenant_id bigint not null default public.tenant_id(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One row per YouTube video per tenant; upsert target.
drop index if exists youtube_videos_yt_video_id_tenant_idx;
create unique index if not exists youtube_videos_yt_video_id_tenant_idx
  on public.youtube_videos (tenant_id, yt_video_id);

alter table public.youtube_videos enable row level security;

-- Public read: only currently-available rows within the caller's tenant.
drop policy if exists "youtube_videos public read" on public.youtube_videos;
create policy "youtube_videos public read" on public.youtube_videos
  for select to anon, authenticated
  using (is_available = true and tenant_id = public.tenant_id());

-- Admin write (super admins manage the catalog; the sync RPC runs as
-- service_role so it is exempt from RLS, but admins may also curate rows).
drop policy if exists "youtube_videos admin all" on public.youtube_videos;
create policy "youtube_videos admin all" on public.youtube_videos
  for all to authenticated
  using (public.is_admin() and tenant_id = public.tenant_id())
  with check (public.is_admin() and tenant_id = public.tenant_id());

-- Update trigger: keep `updated_at` fresh on admin edits.
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_youtube_videos_updated on public.youtube_videos;
create trigger trg_youtube_videos_updated
  before update on public.youtube_videos
  for each row execute function public.touch_updated_at();

-- Grants + sequence access (IDENTITY table writable by authenticated).
grant select on public.youtube_videos to anon, authenticated;
grant select, insert, update, delete on public.youtube_videos to authenticated;
grant usage, select on all sequences in schema public to authenticated;

do $$
declare v_seq text;
begin
  v_seq := pg_get_serial_sequence('public.youtube_videos', 'id');
  if v_seq is not null then
    execute 'grant usage, select on sequence ' || v_seq || ' to authenticated';
  end if;
end $$;

comment on table public.youtube_videos is
  'Free-content catalog of the church YouTube channel (masses, sermons, events) synced by the youtube-sync Edge Function. No payments or access gating.';

-- 2. sync_youtube_videos RPC ------------------------------------------------
-- Single sanctioned write seam for the catalog. Receives the freshly fetched
-- videos as a JSONB array; upserts them within the (locked) tenant and marks
-- any videos absent from this batch as unavailable (removed/made private on
-- YouTube) — preserving row identity for stable references.
create or replace function public.sync_youtube_videos(
  p_channel_id text,
  p_videos jsonb
)
returns jsonb
language plpgsql security definer
set search_path = public as $$
declare
  v_tenant bigint := public.tenant_id();
  v_row jsonb;
  v_yt_id text;
  v_url text;
  v_upserted int := 0;
  v_present text[] := '{}';
begin
  if p_channel_id is null or p_channel_id = '' then
    raise exception 'BAD_REQUEST' using errcode = '22000';
  end if;

  -- Lock the (single-tenant) catalog row set for this run to serialise
  -- overlapping syncs.
  perform 1 from public.youtube_videos where tenant_id = v_tenant for update;

  for v_row in select * from jsonb_array_elements(coalesce(p_videos, '[]'::jsonb)) loop
    v_yt_id := v_row->>'yt_video_id';
    v_url  := v_row->>'yt_url';
    if v_yt_id is null or v_url is null then
      continue; -- skip malformed entries
    end if;

    insert into public.youtube_videos (
      yt_video_id, title, description, thumbnail_url, yt_url,
      published_at, duration_seconds, is_available, synced_at, tenant_id
    )
    values (
      v_yt_id,
      coalesce(v_row->>'title', ''),
      v_row->>'description',
      v_row->>'thumbnail_url',
      v_url,
      (v_row->>'published_at')::timestamptz,
      nullif(v_row->>'duration_seconds', '')::int,
      true,
      now(),
      v_tenant
    )
    on conflict (tenant_id, yt_video_id) do update
      set title = excluded.title,
          description = excluded.description,
          thumbnail_url = excluded.thumbnail_url,
          yt_url = excluded.yt_url,
          published_at = excluded.published_at,
          duration_seconds = excluded.duration_seconds,
          is_available = true,
          synced_at = now();

    v_present := array_append(v_present, v_yt_id);
    v_upserted := v_upserted + 1;
  end loop;

  -- Mark videos missing from this batch as unavailable (deleted/private on YT).
  if array_length(v_present, 1) is not null then
    update public.youtube_videos
      set is_available = false
      where tenant_id = v_tenant
        and is_available = true
        and yt_video_id <> all (v_present);
  else
    -- Empty batch: the channel returned nothing. Leave existing rows available
    -- rather than wiping the catalog on a transient empty response.
    null;
  end if;

  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (
    null, 'sync_youtube_videos', 'youtube_videos', null,
    jsonb_build_object('channel_id', p_channel_id, 'upserted', v_upserted, 'tenant_id', v_tenant)
  );

  return jsonb_build_object('upserted', v_upserted, 'channel_id', p_channel_id);
end $$;

revoke all on function public.sync_youtube_videos(text, jsonb)
  from public, anon, authenticated;
grant execute on function public.sync_youtube_videos(text, jsonb) to service_role;

-- 3. Read view (explicit columns, no SELECT * leak) -------------------------
drop view if exists public.v_sermons;
create view public.v_sermons with (security_invoker = true) as
select id, yt_video_id, title, description, thumbnail_url, yt_url,
       published_at, duration_seconds, tenant_id
from public.youtube_videos
where is_available = true and tenant_id = public.tenant_id();

grant select on public.v_sermons to anon, authenticated;
comment on view public.v_sermons is
  'Public read view of available YouTube sermons/masses for the current tenant.';

-- 4. pg_cron schedule — refresh catalog hourly -----------------------------
-- Calls the youtube-sync Edge Function with the service-role key from vault.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'youtube-sync') then
      perform cron.unschedule('youtube-sync');
    end if;
    perform cron.schedule(
      'youtube-sync',
      '15 * * * *',
      $cron$
        select net.http_post(
          url := case
            when (select decrypted_secret from vault.decrypted_secrets where name = 'SUPABASE_URL' limit 1) ~ '^https?://'
            then (select decrypted_secret from vault.decrypted_secrets where name = 'SUPABASE_URL' limit 1)
            else 'https://' || (select decrypted_secret from vault.decrypted_secrets where name = 'SUPABASE_URL' limit 1)
          end || '/functions/v1/youtube-sync',
          headers := jsonb_build_object(
            'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'SERVICE_ROLE_KEY' limit 1),
            'Content-Type', 'application/json'),
          body := '{}'
        );
      $cron$
    );
  end if;
exception when others then
  raise notice '0073: pg_cron schedule skipped (%)', sqlerrm;
end $$;
