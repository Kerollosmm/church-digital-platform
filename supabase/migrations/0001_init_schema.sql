-- 0001: full schema per master plan §5 + conventions. Phase 0 owns 0001-0003.
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

create type public.app_role as enum ('USER','ADMIN');
create type public.booking_status as enum ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED','COMPLETED','CANCELLED','RESCHEDULED');
create type public.payment_status as enum ('CREATED','PAID','FAILED','REFUNDED','REFUND_PENDING','PENDING');
create type public.video_privacy as enum ('PUBLIC','UNLISTED','PRIVATE');
create type public.complaint_status as enum ('NEW','ASSIGNED','RESOLVED');
do $$
begin
  if not exists (select 1 from pg_type where typname = 'event_handler_type') then
    create type public.event_handler_type as enum ('WHATSAPP','PAYMOB_REFUND','FCM_PUSH','SMS');
  end if;
  if not exists (select 1 from pg_type where typname = 'outbox_status') then
    create type public.outbox_status as enum ('PENDING','PROCESSING','SENT','FAILED');
  end if;
end $$;


create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  phone text not null unique,
  name text not null default '',
  role public.app_role not null default 'USER',
  fcm_token text,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.roles_permissions (
  id bigint generated always as identity primary key,
  role public.app_role not null,
  resource text not null,
  action text not null check (action in ('READ','CREATE','UPDATE','DELETE')),
  unique (role, resource, action)
);

create table public.priests (
  id bigint generated always as identity primary key,
  name text not null,
  photo_url text,
  bio text,
  visitation_hours jsonb not null default '{}'::jsonb,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.services (
  id bigint generated always as identity primary key,
  title_ar text not null,
  description text,
  schedule jsonb not null default '{}'::jsonb,
  location text,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.service_slots (
  id bigint generated always as identity primary key,
  service_id bigint not null references public.services(id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  capacity int not null default 0,
  price int not null default 0,
  status text not null default 'OPEN',
  location text,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.bookings (
  id bigint generated always as identity primary key,
  slot_id bigint not null references public.service_slots(id),
  user_id uuid not null references public.users(id),
  status public.booking_status not null default 'PENDING_PAYMENT',
  paid_amount int not null default 0,
  payment_ref text,
  locked_until timestamptz,
  created_by text not null default 'system',
  notes text,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint bookings_status_check check (status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED','COMPLETED','CANCELLED','RESCHEDULED')),
  constraint bookings_locked_until_check check (locked_until is null or status = 'PENDING_PAYMENT'),
  constraint bookings_paid_amount_check check (paid_amount >= 0)
);

create table public.payments (
  id bigint generated always as identity primary key,
  booking_id bigint not null references public.bookings(id),
  gateway_ref text,
  amount int not null default 0,
  status public.payment_status not null default 'CREATED',
  raw_webhook jsonb,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.waiting_list (
  id bigint generated always as identity primary key,
  slot_id bigint not null references public.service_slots(id),
  user_id uuid not null references public.users(id),
  position int not null,
  status text not null default 'WAITING',
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.videos (
  id bigint generated always as identity primary key,
  title_ar text not null,
  event_date timestamptz not null,
  yt_url text not null,
  price int not null check (price >= 0),
  privacy public.video_privacy not null default 'UNLISTED',
  expires_after_days int,
  uploaded_by uuid,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.video_purchases (
  id bigint generated always as identity primary key,
  video_id bigint not null references public.videos(id),
  user_id uuid not null references public.users(id),
  payment_id bigint not null references public.payments(id),
  access_granted_at timestamptz,
  link_sent_at timestamptz,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.complaints (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.users(id),
  category text not null,
  body_encrypted bytea not null,
  status public.complaint_status not null default 'NEW',
  assigned_to uuid references public.users(id),
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.announcements (
  id bigint generated always as identity primary key,
  title_ar text not null,
  body_ar text not null,
  target_role public.app_role,
  published_at timestamptz not null default now(),
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  user_id uuid,
  action text not null,
  entity_type text not null,
  entity_id bigint,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.whatsapp_outbox (
  id bigint generated always as identity primary key,
  phone text not null,
  template_name text not null,
  params jsonb not null default '{}'::jsonb,
  status text not null default 'PENDING',
  attempts int not null default 0,
  next_attempt_at timestamptz not null default now(),
  tenant_id bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.whatsapp_optins (
  phone text primary key,
  consented_at timestamptz not null default now(),
  source text not null default 'BOOKING',
  tenant_id bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ============================================================
-- Refund requests (must exist before 0027_event_outbox.sql)
-- ============================================================
create table if not exists public.refund_requests (
  id          bigint generated always as identity primary key,
  payment_id  bigint not null references public.payments(id),
  amount      numeric(12,2) not null,
  status      text not null default 'PENDING',
  attempts    int not null default 0,
  next_attempt_at timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);


-- ============================================================
-- RBAC helper functions (must exist before 0002_rls_baseline.sql)
-- 0002 defines policies using is_admin(); these must be available.
-- 0025 re-creates them with CREATE OR REPLACE (idempotent).
-- ============================================================

create or replace function public.tenant_id()
returns bigint
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'tenant_id',
    '1'
  )::bigint
$$;

create or replace function public.current_user_role()
returns text
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (select u.role::text from public.users u
     where u.id = auth.uid() and u.deleted_at is null),
    'anon'
  )
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.current_user_role() in ('ADMIN','SUPER_ADMIN')
$$;

create or replace function public.is_admin_or_priest()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.current_user_role() in ('ADMIN','PRIEST','SUPER_ADMIN')
$$;

create or replace function public.is_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.current_user_role() = 'SUPER_ADMIN'
$$;

grant execute on function public.tenant_id() to anon, authenticated, service_role;
grant execute on function public.current_user_role() to anon, authenticated, service_role;
grant execute on function public.is_admin() to anon, authenticated, service_role;
grant execute on function public.is_admin_or_priest() to anon, authenticated, service_role;
grant execute on function public.is_super_admin() to anon, authenticated, service_role;

-- RLS for refund_requests (placed after is_admin() definition)
alter table public.refund_requests enable row level security;

create policy "refund_requests_admin_all" on public.refund_requests
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());
