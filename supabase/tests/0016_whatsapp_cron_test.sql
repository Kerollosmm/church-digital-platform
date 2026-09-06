BEGIN;

do $$
begin
  if not exists (select 1 from cron.job where jobname = 'event-dispatcher')
  then raise exception 'FAIL: cron job event-dispatcher must be scheduled'; end if;
end $$;

ROLLBACK;
