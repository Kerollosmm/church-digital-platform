-- 0027: unified event outbox (replaces whatsapp_outbox + refund_requests + 2 crons)
do $$
begin
  if not exists (select 1 from pg_type where typname = 'event_handler_type') then
    create type public.event_handler_type as enum ('WHATSAPP','PAYMOB_REFUND','FCM_PUSH','SMS');
  end if;
  if not exists (select 1 from pg_type where typname = 'outbox_status') then
    create type public.outbox_status as enum ('PENDING','PROCESSING','SENT','FAILED');
  end if;
end $$;

create table public.event_outbox (
  id bigint generated always as identity primary key,
  tenant_id bigint not null default public.tenant_id(),
  handler_type public.event_handler_type not null,
  payload jsonb not null default '{}'::jsonb,
  status public.outbox_status not null default 'PENDING',
  attempts int not null default 0 check (attempts between 0 and 5),
  next_attempt_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint event_outbox_whatsapp_template_check check (
    handler_type <> 'WHATSAPP'
    or payload->>'template_name' in ('booking_confirmed','payment_received','booking_cancelled',
                                    'booking_rescheduled','booking_apology','otp_auth',
                                    'booking_payment_received','booking_offer')
  )
);
alter table public.event_outbox enable row level security;
-- no policies: only SECURITY DEFINER RPCs (enqueue) and the dispatcher (service role) touch it.

create index idx_event_outbox_drain on public.event_outbox (status, next_attempt_at)
  where status = 'PENDING';

-- migrate queued rows (deployed DBs; fresh resets start empty)
insert into public.event_outbox (tenant_id, handler_type, payload, status, attempts, next_attempt_at, created_at)
select coalesce(o.tenant_id, 1), 'WHATSAPP',
       jsonb_build_object('phone', o.phone, 'template_name', o.template_name, 'params', o.params),
       o.status::text::public.outbox_status, o.attempts, o.next_attempt_at, o.created_at
from public.whatsapp_outbox o;
insert into public.event_outbox (tenant_id, handler_type, payload, status, attempts, next_attempt_at, created_at)
select 1, 'PAYMOB_REFUND',
       jsonb_build_object('payment_id', r.payment_id, 'amount', r.amount),
       'PENDING', r.attempts, r.next_attempt_at, r.created_at
from public.refund_requests r;

drop table public.whatsapp_outbox;
drop table public.refund_requests;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'whatsapp-sender') then
    perform cron.unschedule('whatsapp-sender');
  end if;
  if exists (select 1 from cron.job where jobname = 'refund-drain') then
    perform cron.unschedule('refund-drain');
  end if;
end $$;
