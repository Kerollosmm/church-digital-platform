-- 0019: paid videos (M3). production flow always UNLISTED.
do $$ begin
  create type public.video_privacy as enum ('PUBLIC', 'UNLISTED', 'PRIVATE');
exception when duplicate_object then null; end $$;

create table if not exists public.videos (
  id bigint generated always as identity primary key,
  title_ar text not null,
  event_date timestamptz not null,
  yt_url text not null,
  price int not null check (price >= 0),
  privacy public.video_privacy not null default 'UNLISTED',
  expires_after_days int,
  uploaded_by uuid,
  tenant_id bigint not null default public.tenant_id(),
  created_at timestamptz not null default now()
);

create table if not exists public.video_purchases (
  id bigint generated always as identity primary key,
  video_id bigint not null references public.videos(id),
  user_id uuid not null,
  payment_id bigint not null references public.payments(id),
  access_granted_at timestamptz,
  link_sent_at timestamptz,
  tenant_id bigint not null default public.tenant_id(),
  created_at timestamptz not null default now()
);
alter table public.video_purchases enable row level security;
drop policy if exists "video_purchases own read" on public.video_purchases;
create policy "video_purchases own read" on public.video_purchases for select to authenticated
  using (user_id = auth.uid() and tenant_id = public.tenant_id());

alter table public.videos enable row level security;
drop policy if exists "videos public read" on public.videos;
-- listing rows only (title/price/event_date); UNLISTED rows are invisible until purchased
create policy "videos public read" on public.videos for select to anon, authenticated
  using (tenant_id = public.tenant_id() and (privacy = 'PUBLIC'
    or (auth.uid() is not null and exists (
      select 1 from public.video_purchases vp
      where vp.video_id = videos.id and vp.user_id = auth.uid() and vp.access_granted_at is not null))));
drop policy if exists "videos admin write" on public.videos;
create policy "videos admin write" on public.videos for all to authenticated
  using (public.is_admin_or_priest() and tenant_id = public.tenant_id())
  with check (public.is_admin_or_priest() and tenant_id = public.tenant_id());

-- the ONLY way to read yt_url: purchasers' view (UNLISTED links stay secret pre-purchase)
drop view if exists public.v_my_videos;
create view public.v_my_videos with (security_invoker = true) as
select v.id, v.title_ar, v.event_date, v.yt_url, v.price
from public.videos v
join public.video_purchases vp on vp.video_id = v.id
where vp.user_id = auth.uid() and vp.access_granted_at is not null
  and v.tenant_id = public.tenant_id();

alter table public.payments add column if not exists video_id bigint references public.videos(id);
alter table public.payments alter column booking_id drop not null;

-- purchase: create payment (CREATED) + purchase row; checkout edge fn issues the intent
create or replace function public.purchase_video(p_video_id bigint)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_role text := public.current_user_role();
  v_video public.videos;
  v_pay bigint;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED' using errcode = '28000'; end if;
  if v_role <> 'PARISHIONER' then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
  select * into v_video from public.videos where id = p_video_id and privacy = 'UNLISTED';
  if v_video is null then raise exception 'VIDEO_NOT_FOUND'; end if;
  if exists (select 1 from public.video_purchases where video_id = p_video_id and user_id = v_user and access_granted_at is not null)
  then raise exception 'ALREADY_PURCHASED'; end if;
  insert into public.payments (video_id, amount, status, gateway_ref, tenant_id)
  values (p_video_id, v_video.price, 'CREATED', null, public.tenant_id())
  returning id into v_pay;
  insert into public.video_purchases (video_id, user_id, payment_id, tenant_id)
  values (p_video_id, v_user, v_pay, public.tenant_id());
  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (v_user, 'purchase_video', 'payments', v_pay, jsonb_build_object('video_id', p_video_id));
  return v_pay;
end $$;

-- webhook landing for video payments (called by paymob-webhook when payment has video_id)
create or replace function public.apply_video_payment(p_payment_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_pay public.payments;
  v_purchase public.video_purchases;
  v_video public.videos;
begin
  select * into v_pay from public.payments where id = p_payment_id for update;
  if v_pay is null then raise exception 'PAYMENT_NOT_FOUND'; end if;
  if v_pay.status = 'PAID' then return; end if;
  update public.payments set status = 'PAID' where id = v_pay.id;
  select * into v_purchase from public.video_purchases where payment_id = v_pay.id;
  select * into v_video from public.videos where id = v_pay.video_id;
  update public.video_purchases set access_granted_at = now(), link_sent_at = now()
  where payment_id = v_pay.id;
  if v_purchase.user_id is not null then
    insert into public.event_outbox (handler_type, payload)
    select 'WHATSAPP', jsonb_build_object('phone', u.phone, 'template_name', 'payment_received', 'params', jsonb_build_object('link', v_video.yt_url))
    from public.users u where u.id = v_purchase.user_id and u.phone is not null
    and not exists (select 1 from public.event_outbox w
                    where w.handler_type = 'WHATSAPP'
                      and w.payload->>'template_name' = 'payment_received'
                      and (w.payload->'params'->>'link' = v_video.yt_url or w.payload->>'link' = v_video.yt_url)
                      and w.payload->>'phone' = u.phone);
  end if;
  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (null, 'apply_video_payment', 'payments', v_pay.id, jsonb_build_object('video_id', v_pay.video_id));
end $$;
