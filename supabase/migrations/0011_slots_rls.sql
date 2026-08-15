-- 0011: service_slots — ADMIN/PRIEST write only (parishioners read via v_available_slots)
drop policy if exists "service_slots admin write" on public.service_slots;
create policy "service_slots admin write" on public.service_slots for all to authenticated
  using (public.is_admin_or_priest() and tenant_id = public.tenant_id())
  with check (public.is_admin_or_priest() and tenant_id = public.tenant_id());
