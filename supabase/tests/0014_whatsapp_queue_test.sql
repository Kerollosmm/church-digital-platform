do $$
begin
  -- registry CHECK exists
  insert into public.event_outbox (handler_type, payload)
  values ('WHATSAPP', jsonb_build_object('phone', '+201000000000', 'template_name', 'booking_confirmed', 'params', '{}'::jsonb));
  begin
    insert into public.event_outbox (handler_type, payload)
    values ('WHATSAPP', jsonb_build_object('phone', '+201000000000', 'template_name', 'UNKNOWN_TEMPLATE', 'params', '{}'::jsonb));
    raise exception 'FAIL: unknown template must be rejected by CHECK';
  exception when check_violation then null; end;
  -- drain index exists
  if not exists (select 1 from pg_indexes where indexname = 'idx_event_outbox_drain')
  then raise exception 'FAIL: drain index idx_event_outbox_drain missing'; end if;
  -- cron check: event-dispatcher present, legacy crons absent
  if not exists (select 1 from cron.job where jobname = 'event-dispatcher')
  then raise exception 'FAIL: event-dispatcher cron job missing'; end if;
  if exists (select 1 from cron.job where jobname in ('whatsapp-sender', 'refund-drain'))
  then raise exception 'FAIL: legacy crons must be unscheduled'; end if;
  -- optins PK + source check
  insert into public.whatsapp_optins (phone, source) values ('+201000000001', 'MANUAL');
  begin
    insert into public.whatsapp_optins (phone, source) values ('+201000000001', 'MANUAL');
    raise exception 'FAIL: duplicate optin phone must violate PK';
  exception when unique_violation then null; end;
end $$;
