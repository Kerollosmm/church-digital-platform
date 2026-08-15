-- 0006: announcements RLS — public read (published only), ADMIN/PRIEST write
drop policy if exists "announcements public read" on public.announcements;
create policy "announcements public read" on public.announcements for select to anon, authenticated
  using (published_at is not null and published_at <= now() and tenant_id = public.tenant_id());
drop policy if exists "announcements admin write" on public.announcements;
create policy "announcements admin write" on public.announcements for all to authenticated
  using (public.is_admin_or_priest() and tenant_id = public.tenant_id())
  with check (public.is_admin_or_priest() and tenant_id = public.tenant_id());
