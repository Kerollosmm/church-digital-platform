-- 0086: prod drift purge + reify v_services
-- Prod predates the migration baseline (history partially "repaired" without
-- executing), so objects that later migrations were supposed to drop/create
-- diverged. Verified 2026-09-06 by full schema diff (prod dump post-0084 vs
-- local reset). Every drop is IF EXISTS -> no-op on fresh local resets.
-- 0085 (immediately before this) rescues live rows out of drift venues.
--
-- Residual drift intentionally NOT touched: booking_status enum on prod has
-- 4 extra labels (SUBMITTED, REJECTED, PARTIALLY_PAID, PAID) that cannot be
-- dropped from a PG enum type.
begin;

-- ---------------------------------------------------------------------------
-- 1. Reify v_services (prod-only view; mobile booking home screen reads it).
--    Definition copied verbatim from prod. security_invoker=true so RLS on
--    services/service_slots still applies.
-- ---------------------------------------------------------------------------
create or replace view public.v_services with (security_invoker = true) as
select s.id,
       s.title_ar,
       s.description,
       s.location,
       min(sl.starts_at) filter
         (where sl.status <> 'CLOSED' and sl.starts_at > now()) as next_slot_starts_at,
       min(sl.price) filter
         (where sl.status <> 'CLOSED' and sl.starts_at > now()) as price_from,
       s.tenant_id
from public.services s
left join public.service_slots sl on sl.service_id = s.id
where s.tenant_id = public.tenant_id()
group by s.id;

grant all on public.v_services to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Complaints: replace drifted pre-0005 policy with the repo's version
--    (0005 never physically ran on prod).
-- ---------------------------------------------------------------------------
drop policy if exists "complaints assign write" on public.complaints;
drop policy if exists "complaints_admin_assign" on public.complaints;
create policy "complaints_admin_assign" on public.complaints for update to authenticated
using (public.is_admin() and tenant_id = public.tenant_id())
with check (
  public.is_admin()
  and tenant_id = public.tenant_id()
  and (assigned_to is null or assigned_to <> auth.uid())
);

-- ---------------------------------------------------------------------------
-- 3. Drop drift functions (17 = 15 functions + 2 bigint-keyed overloads).
--    KEEP: public.admin_record_cash_payment(uuid, bigint, text) — repo-clean.
-- ---------------------------------------------------------------------------
drop function if exists public.admin_apply_pastoral_fee_waiver(bigint, bigint, text, text);
drop function if exists public.assign_clergy_to_event(bigint, bigint);
drop function if exists public.book_family_slots(bigint, bigint[], boolean);
drop function if exists public.cancel_event_booking(bigint, text);
drop function if exists public.get_clergy_daily_itinerary(bigint, date);
drop function if exists public.manage_family_members(text, bigint, text, text, text, date, text);
drop function if exists public.rapid_emergency_funeral_booking(text, text, bigint, bigint, timestamptz, integer, text);
drop function if exists public.record_cash_payment(bigint, integer, text);
drop function if exists public.set_updated_at();
drop function if exists public.superadmin_create_extra_service(text, text, text, text, text, bigint, boolean, integer);
drop function if exists public.superadmin_link_service_to_event_type(bigint, bigint, boolean);
drop function if exists public.superadmin_toggle_extra_service_status(bigint, boolean);
drop function if exists public.superadmin_update_extra_service(bigint, text, text, text, text, text, bigint, boolean, integer);
drop function if exists public.superadmin_upsert_event_type(bigint, text, bigint, boolean);
drop function if exists public.superadmin_upsert_extra_service(bigint, text, bigint, boolean, boolean);
drop function if exists public.admin_record_cash_payment(bigint, integer, text, text);
drop function if exists public.admin_record_cash_payment(bigint, bigint, text, text);

-- ---------------------------------------------------------------------------
-- 4. Payments: drop drift columns + index (prod-only parallel payment impl).
-- ---------------------------------------------------------------------------
drop index if exists public.payments_event_booking_idx;

alter table public.payments
  drop column if exists event_booking_id,
  drop column if exists method,
  drop column if exists recorded_by,
  drop column if exists received_at,
  drop column if exists receipt_reference;

-- ---------------------------------------------------------------------------
-- 5. Drop drift tables (all FKs are internal to this set — verified in dump).
--    Single statement so inter-table dependencies resolve atomically.
--    whatsapp_outbox/refund_requests rows were already migrated by 0027;
--    venues rows were rescued into venues_resources by 0085.
-- ---------------------------------------------------------------------------
drop table if exists
  public.alerts,
  public.attendance,
  public.clergy_profiles,
  public.family_members,
  public.households,
  public.members,
  public.visits,
  public.refund_requests,
  public.venues,
  public.whatsapp_outbox;

-- ---------------------------------------------------------------------------
-- 6. Drop drift enums (no remaining users after steps 3-5).
-- ---------------------------------------------------------------------------
drop type if exists public.alert_type;
drop type if exists public.attendance_method;
drop type if exists public.member_status;
drop type if exists public.payment_method;
drop type if exists public.pricing_mode;

-- ---------------------------------------------------------------------------
-- 7. Kill legacy cron jobs if they survived (0027's unschedule never
--    physically ran on prod; the crons reference dropped tables).
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from cron.job where jobname = 'whatsapp-sender') then
    perform cron.unschedule('whatsapp-sender');
  end if;
  if exists (select 1 from cron.job where jobname = 'refund-drain') then
    perform cron.unschedule('refund-drain');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 8. H-3: pin search_path on the 19 SECURITY DEFINER functions that prod
--    still carries without a hardened search_path (generated from local DB).
-- ---------------------------------------------------------------------------
alter function public.admin_pin_status() set search_path = public, extensions, pg_temp;
alter function public.cancel_booking(p_booking_id bigint) set search_path = public, pg_temp;
alter function public.complete_booking(p_booking_id bigint) set search_path = public, pg_temp;
alter function public.confirm_booking(p_booking_id bigint) set search_path = public, pg_temp;
alter function public.decrypt_complaint(p_complaint_id bigint) set search_path = public, extensions, pg_temp;
alter function public.emergency_override(p_booking_id bigint, p_new_slot_id bigint, p_refund boolean) set search_path = public, pg_temp;
alter function public.enqueue_fcm_booking_status_push() set search_path = public, pg_temp;
alter function public.expire_stale_bookings() set search_path = public, pg_temp;
alter function public.join_waiting_list(p_slot_id bigint) set search_path = public, pg_temp;
alter function public.manual_book(p_slot_id bigint, p_phone text, p_opt_in boolean, p_notes text) set search_path = public, pg_temp;
alter function public.materialize_analytics() set search_path = public, pg_temp;
alter function public.promote_waiting_list(p_slot_id bigint) set search_path = public, pg_temp;
alter function public.reset_admin_pin(p_target uuid) set search_path = public, extensions, pg_temp;
alter function public.set_admin_pin(p_pin text) set search_path = public, extensions, pg_temp;
alter function public.submit_complaint_secure(p_category text, p_body text) set search_path = public, extensions, pg_temp;
alter function public.sync_offline_mutations(p_mutations jsonb) set search_path = public, extensions, pg_temp;
alter function public.transition_booking_status(p_booking_id bigint, p_new_status booking_status, p_action text, p_reason text, p_metadata jsonb) set search_path = public, pg_temp;
alter function public.update_fcm_token(p_token text) set search_path = public, pg_temp;
alter function public.verify_admin_pin(p_pin text) set search_path = public, extensions, pg_temp;

commit;
