-- 0085: rescue live rows from drift venues before the purge migration drops it.
-- Prod's drift table public.venues holds 2 real venue records
-- (الكنيسة الكبرى, قاعة المناسبات) that exist nowhere else — venues_resources
-- is empty on prod. Rehome them before 0086 drops the table.
-- capacity has no target column (0073 dropped it) and is intentionally
-- not carried over. Guarded: no-op on fresh local resets (no venues table).
begin;

do $$
begin
  if exists (select 1 from information_schema.tables
             where table_schema = 'public' and table_name = 'venues') then
    insert into public.venues_resources (name_ar, location_details_ar, is_active, tenant_id)
    select v.name_ar, v.location, v.active, v.tenant_id
    from public.venues v
    where not exists (
      select 1 from public.venues_resources vr
      where vr.tenant_id = v.tenant_id
        and vr.name_ar = v.name_ar
        and vr.deleted_at is null
    );
  end if;
end $$;

commit;
