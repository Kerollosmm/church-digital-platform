-- 0029: fcm token update rpc + booking status change fcm push trigger
create or replace function public.update_fcm_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  update public.users
     set fcm_token = p_token,
         updated_at = now()
   where id = auth.uid();
end;
$$;

grant execute on function public.update_fcm_token(text) to authenticated, service_role;

create or replace function public.enqueue_fcm_booking_status_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fcm_token text;
  v_title text;
  v_body text;
begin
  if (TG_OP = 'UPDATE' and OLD.status = NEW.status) then
    return NEW;
  end if;

  if NEW.status not in ('AWAITING_CALL', 'CONFIRMED', 'CANCELLED') then
    return NEW;
  end if;

  select fcm_token into v_fcm_token
    from public.users
   where id = NEW.user_id;

  if v_fcm_token is null or v_fcm_token = '' then
    return NEW;
  end if;

  v_title := case NEW.status
    when 'AWAITING_CALL' then 'Booking Pending Confirmation'
    when 'CONFIRMED'     then 'Booking Confirmed'
    when 'CANCELLED'     then 'Booking Cancelled'
  end;

  v_body := case NEW.status
    when 'AWAITING_CALL' then 'Your booking is awaiting call confirmation.'
    when 'CONFIRMED'     then 'Your booking has been confirmed.'
    when 'CANCELLED'     then 'Your booking has been cancelled.'
  end;

  insert into public.event_outbox (tenant_id, handler_type, payload)
  values (
    NEW.tenant_id,
    'FCM_PUSH',
    jsonb_build_object(
      'fcm_token', v_fcm_token,
      'title', v_title,
      'body', v_body,
      'data', jsonb_build_object('booking_id', NEW.id::text, 'status', NEW.status::text)
    )
  );

  return NEW;
end;
$$;

drop trigger if exists trg_fcm_booking_status on public.bookings;
create trigger trg_fcm_booking_status
  after insert or update on public.bookings
  for each row execute function public.enqueue_fcm_booking_status_push();
