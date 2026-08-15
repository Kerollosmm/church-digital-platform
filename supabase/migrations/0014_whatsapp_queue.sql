-- 0014: whatsapp_optins constraint
alter table public.whatsapp_optins
  drop constraint if exists whatsapp_optins_source_check;
alter table public.whatsapp_optins
  add constraint whatsapp_optins_source_check check (source in ('BOOKING','MANUAL','REGISTRATION'));
