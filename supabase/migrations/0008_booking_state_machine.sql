-- 0008: booking state machine + whatsapp_optins (needed by book_slot)
create table if not exists public.whatsapp_optins (
  phone text primary key,
  consented_at timestamptz not null default now(),
  source text not null default 'BOOKING'
);
alter table public.whatsapp_optins enable row level security;

drop policy if exists "whatsapp_optins read own" on public.whatsapp_optins;
create policy "whatsapp_optins read own" on public.whatsapp_optins for select to authenticated
  using (phone = (select phone from public.users where id = auth.uid()) or public.is_admin());

alter table public.bookings drop constraint if exists bookings_status_check;
alter table public.bookings add constraint bookings_status_check
  check (status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED','COMPLETED','CANCELLED','RESCHEDULED'));
alter table public.bookings drop constraint if exists bookings_locked_until_check;
alter table public.bookings add constraint bookings_locked_until_check
  check (locked_until is null or status = 'PENDING_PAYMENT');
alter table public.bookings drop constraint if exists bookings_paid_amount_check;
alter table public.bookings add constraint bookings_paid_amount_check check (paid_amount >= 0);

create or replace function public.enforce_booking_status_transition() returns trigger
language plpgsql as $$
begin
  if old.status = new.status then return new; end if;
  if not (
    (old.status = 'PENDING_PAYMENT' and new.status in ('AWAITING_CALL','CANCELLED','RESCHEDULED')) or
    (old.status = 'AWAITING_CALL'    and new.status in ('CONFIRMED','CANCELLED','RESCHEDULED')) or
    (old.status = 'CONFIRMED'        and new.status in ('COMPLETED','CANCELLED','RESCHEDULED'))
  ) then
    raise exception 'INVALID_STATUS_TRANSITION % -> %', old.status, new.status;
  end if;
  return new;
end $$;
drop trigger if exists bookings_status_guard on public.bookings;
create trigger bookings_status_guard
  before update on public.bookings
  for each row execute function public.enforce_booking_status_transition();

create or replace function public.book_slot(p_slot_id bigint, p_opt_in boolean default false)
returns public.bookings language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_role text := public.current_user_role();
  v_phone text;
  v_slot public.service_slots;
  v_active int;
  v_mine int;
  v_book public.bookings;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED' using errcode = '28000'; end if;
  if v_role not in ('PARISHIONER','ADMIN','PRIEST') then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
  select * into v_slot from public.service_slots where id = p_slot_id for update;
  if v_slot is null or v_slot.status = 'CLOSED' or v_slot.starts_at <= now()
  then raise exception 'SLOT_UNAVAILABLE' using errcode = 'P0001'; end if;
  select count(*) into v_mine from public.bookings
  where user_id = v_user and status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED');
  if v_mine >= 3 then raise exception 'TOO_MANY_ACTIVE_BOOKINGS' using errcode = 'P0001'; end if;
  if exists (select 1 from public.bookings
             where slot_id = p_slot_id and user_id = v_user
               and status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED'))
  then raise exception 'ALREADY_BOOKED_SLOT' using errcode = 'P0001'; end if;
  select public.active_booking_count(p_slot_id) into v_active;
  if v_active >= v_slot.capacity then raise exception 'SLOT_FULL' using errcode = 'P0001'; end if;
  if p_opt_in then
    select phone into v_phone from public.users where id = v_user;
    if v_phone is not null then
      insert into public.whatsapp_optins (phone, source) values (v_phone, 'BOOKING')
      on conflict (phone) do update set consented_at = now();
    end if;
  end if;
  insert into public.bookings (slot_id, user_id, status, paid_amount, locked_until, created_by, tenant_id)
  values (p_slot_id, v_user, 'PENDING_PAYMENT', v_slot.price, now() + interval '20 minutes', 'system', public.tenant_id())
  returning * into v_book;
  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (v_user, 'book_slot', 'bookings', v_book.id,
          jsonb_build_object('slot_id', p_slot_id, 'opt_in', p_opt_in));
  return v_book;
end $$;

create or replace function public.promote_waiting_list(p_slot_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_wait record;
  v_book public.bookings;
  v_slot public.service_slots;
begin
  select * into v_wait from public.waiting_list
  where slot_id = p_slot_id and status = 'WAITING' order by position limit 1;
  if v_wait is null then return; end if;
  begin
    select * into v_slot from public.service_slots where id = p_slot_id for update;
    if v_slot is null or v_slot.status = 'CLOSED' then return; end if;
    if public.active_booking_count(p_slot_id, true) >= v_slot.capacity then return; end if;
    insert into public.bookings (slot_id, user_id, status, locked_until, created_by, tenant_id)
    values (p_slot_id, v_wait.user_id, 'PENDING_PAYMENT', now() + interval '10 minutes', 'system', public.tenant_id())
    returning * into v_book;
  end;
  update public.waiting_list set status = 'OFFERED' where id = v_wait.id;
  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (null, 'promote_waiting_list', 'bookings', v_book.id,
          jsonb_build_object('waiting_list_id', v_wait.id));
end $$;

create or replace function public.cancel_booking(p_booking_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_role text := public.current_user_role();
  v_book public.bookings;
begin
  select * into v_book from public.bookings where id = p_booking_id for update;
  if v_book is null then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_book.user_id <> v_user and v_role not in ('ADMIN','PRIEST','SUPER_ADMIN')
  then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
  v_book := public.transition_booking_status(p_booking_id, 'CANCELLED', 'cancel_booking');
  if exists (select 1 from public.waiting_list where slot_id = v_book.slot_id and status = 'WAITING') then
    perform public.promote_waiting_list(v_book.slot_id);
  end if;
end $$;

create or replace function public.confirm_booking(p_booking_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_role text := public.current_user_role();
begin
  if v_role not in ('ADMIN','PRIEST','SUPER_ADMIN') then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
  if not exists (select 1 from public.bookings where id = p_booking_id and status = 'AWAITING_CALL')
  then raise exception 'INVALID_TRANSITION: must be AWAITING_CALL'; end if;
  perform public.transition_booking_status(p_booking_id, 'CONFIRMED', 'confirm_booking');
end $$;

create or replace function public.complete_booking(p_booking_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_role text := public.current_user_role();
begin
  if v_role not in ('ADMIN','PRIEST','SUPER_ADMIN') then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
  if not exists (select 1 from public.bookings where id = p_booking_id and status = 'CONFIRMED')
  then raise exception 'INVALID_TRANSITION: must be CONFIRMED'; end if;
  perform public.transition_booking_status(p_booking_id, 'COMPLETED', 'complete_booking');
end $$;

create or replace function public.join_waiting_list(p_slot_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'AUTH_REQUIRED' using errcode = '28000'; end if;
  if exists (select 1 from public.bookings where slot_id = p_slot_id
             and status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED'))
  then
    insert into public.waiting_list (slot_id, user_id, position, status, tenant_id)
    select p_slot_id, v_user, coalesce(max(position),0) + 1, 'WAITING', public.tenant_id()
    from public.waiting_list where slot_id = p_slot_id;
    insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
    values (v_user, 'join_waiting_list', 'waiting_list', p_slot_id, '{}'::jsonb);
  else
    raise exception 'SLOT_AVAILABLE: no need to wait';
  end if;
end $$;
