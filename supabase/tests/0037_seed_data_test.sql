\set ON_ERROR_STOP on

begin;

-- Verify seeded services
do $$
declare
  v_services_count int;
  v_priests_count int;
  v_slots_count int;
begin
  select count(*) into v_services_count from public.services;
  if v_services_count < 3 then
    raise exception 'Expected at least 3 services, found %', v_services_count;
  end if;

  select count(*) into v_priests_count from public.priests;
  if v_priests_count < 2 then
    raise exception 'Expected at least 2 priests, found %', v_priests_count;
  end if;

  select count(*) into v_slots_count 
  from public.service_slots 
  where starts_at > now() and greatest(capacity - public.active_booking_count(id), 0) > 0;
  
  if v_slots_count < 6 then
    raise exception 'Expected at least 6 future available service slots, found %', v_slots_count;
  end if;
end;
$$;

rollback;
