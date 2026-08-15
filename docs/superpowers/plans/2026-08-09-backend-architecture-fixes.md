# Backend Architecture Fixes — Implementation Plan

**Date:** 2026-08-09 · **Supersedes:** `docs/superpowers/analysis/2026-08-09-architecture-deepening.md`
**Note on discrepancies:** the analysis doc describes tables (e.g. `tenants`, `service_settings`) and migrations that do not exist in `supabase/migrations/`. Where the doc conflicts with the actual migrations, **the migrations win** — every schema/column/reference below was copied from the real files (0001–0023).
**Scope:** Supabase only (migrations 0024–0027, edge functions, tests). Flutter side: `2026-08-09-mobile-architecture-fixes.md`.
**Workflow:** test-first per task (failing test → implement → run → PASS → commit). Commits: `(backend) fix: <summary>`.

## Objective

1. **Single writer for booking status.** `book_slot`, `cancel_booking`, `confirm_booking`, `complete_booking`, `apply_payment`, `expire_stale_bookings`, `emergency_override`, `promote_waiting_list` each hand-roll `UPDATE bookings` + `INSERT audit_log`, and the `bookings` audit trigger (0002) writes a *second* row per change → every transition double-audits. Fix: one SECURITY DEFINER engine `transition_booking_status()`; drop `trg_bookings_audit` (bookings audit = engine-owned; payments/complaints stay trigger-owned).
2. **Correct availability for parishioners.** `v_available_slots` and `v_schedule_today` are `security_invoker` views; the `bookings` RLS (`p0_bookings_read_own`) makes their active-count join see only the caller's own rows → a parishioner sees "AVAILABLE" on fully booked slots. Fix: central `active_booking_count()` SECURITY DEFINER helper used inside the views.
3. **RBAC helpers.** ~15 policies repeat `current_user_role() in ('ADMIN','PRIEST','SUPER_ADMIN')` / admin-only clauses. Centralize in `is_admin()` / `is_admin_or_priest()` / `is_super_admin()`.
4. **Complaints crypto in-DB.** `complaints-encrypt`/`complaints-decrypt` edge functions → `pgp_sym_encrypt/decrypt` + Vault key `COMPLAINTS_KEY`. `body_encrypted` stays `bytea`, never exposed (0005 deny-select already).
5. **Unified outbox.** `whatsapp_outbox` (0001/0012/0014) + `refund_requests` (0012) with two crons (`whatsapp-sender` 0016, `refund-drain` 0018) → one `event_outbox` table + one `event-dispatcher` edge function + one cron. Delete `whatsapp-sender` and `paymob-refund` edge functions.
6. **Edge-function seams.** Shared client factory `_shared/client.ts`; `analytics-export` (the only function constructing clients inside the handler) refactored to injected deps; behavior otherwise identical.

## Architecture

- **Engine:** `transition_booking_status(p_booking_id bigint, p_new_status booking_status, p_action text, p_reason text default null, p_metadata jsonb default '{}')` → `bookings` row. Locks `FOR UPDATE`, re-asserts ownership/role gates (SECURITY DEFINER must not widen access), `UPDATE`s (transition validation stays in the `bookings_status_guard` trigger from 0008 — the engine does not re-implement it), writes the single audit row. Callers: `cancel_booking` (keeps waiting-list promote), `confirm_booking`, `complete_booking` (keep their pre-checks for good errors), `apply_payment`, `expire_stale_bookings`, `emergency_override` (reschedule leg). Create-paths (`book_slot`, `promote_waiting_list` insert leg, `manual_book`, `emergency_override` new-booking leg) keep their own INSERT + audit row.
- **Count helper:** `active_booking_count(p_slot_id bigint, p_include_expired_locks boolean default false)`. Guarded (`false`, default): `status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED') and (status <> 'PENDING_PAYMENT' or locked_until > now())` — exactly the predicate from 0007. Unguarded (`true`): all three statuses regardless of lock age — exactly the predicate from 0008/0015/0017. Callers: `book_slot` (false), views (false), `promote_waiting_list` (true), `manual_book` (true), `emergency_override` (true).
- **Outbox:** `event_handler_type` enum (`WHATSAPP`,`PAYMOB_REFUND`,`FCM_PUSH`,`SMS`) + `outbox_status` enum (`PENDING`,`PROCESSING`,`SENT`,`FAILED`). `FCM_PUSH`/`SMS` reserved: unknown handler ⇒ FAILED (tested, no stub). Dispatcher = port of whatsapp-sender drain (templates, opt-in, ar, v20.0, batch-10/limit-100, backoff `30s*2^attempts`, max 5) + paymob-refund drain (auth token → refund per row → `payments.status='REFUNDED'`, max 3 attempts, no backoff).
- **Enums in 0001 (back-propagation, checklist 1):** add the two new enum types guarded, next to the existing block.

## Tech Stack

Postgres 16 + RLS + SECURITY DEFINER RPCs (existing); pgcrypto (`pgp_sym_encrypt`); Vault; pg_cron + pg_net (existing pattern from 0013/0016); Deno edge functions with injected deps (existing pattern from `whatsapp-sender`/`paymob-refund`).

## Task List

| # | Files | Deliverable |
|---|---|---|
| 1 | 0024 + edits to 0007, 0008, 0010, 0012, 0015, 0017 + `tests/0024_*` + `0007`/`0008` test updates | Transition engine + count helper + view availability fix |
| 2 | 0025 + edits to 0002, 0004, 0005, 0006, 0008, 0011, 0019, 0023 + `tests/0025_*` | RBAC helpers |
| 3 | 0026 + delete `complaints-encrypt`, `complaints-decrypt` + `tests/0026_*` | Complaints pgp in-DB |
| 4 | 0027 + edits to 0012, 0014, 0016, 0017, 0019 + delete 0018, `whatsapp-sender`, `paymob-refund` + new `event-dispatcher` + tests + e2e update | Unified outbox + dispatcher |
| 5 | `_shared/client.ts` + `analytics-export` + serve() closures + tests | Edge-function seams |

Tests run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/XXXX_name.sql` (no output, exit 0); `deno test --allow-env supabase/functions/<name>/`. Append new test files to `supabase/tests/run_all.sql`.

---

## Task 1 — Transition engine + count helper + availability fix

**Schema (from 0001):** `bookings(id, slot_id, user_id, status, paid_amount, payment_ref, locked_until, created_by, notes, tenant_id, ...)`; `bookings_status_check`, `bookings_locked_until_check` (locked_until null or status='PENDING_PAYMENT'); `service_slots(id, service_id, starts_at, ends_at, capacity, price, status, location, tenant_id, ...)`; `audit_log(id, user_id, action, entity_type, entity_id, meta, created_at)`.

### Step 1 — failing test `supabase/tests/0024_transition_engine_test.sql`

DO-block style like `0008_booking_state_machine_test.sql` (explicit fixtures — checklist 3):

```sql
-- 0024: transition engine + active_booking_count
do $$
declare
  v_user uuid; v_admin uuid; v_slot bigint; v_book bigint; v_other_book bigint;
  v_n int; v_res public.bookings; v_old_audit int;
begin
  -- fixtures
  insert into public.users (id, phone, name, role, tenant_id)
  values ('00000000-0000-0000-0000-000000000001', '+201000000001', 'parishioner', 'PARISHIONER', 1);
  insert into public.users (id, phone, name, role, tenant_id)
  values ('00000000-0000-0000-0000-000000000002', '+201000000002', 'admin', 'ADMIN', 1);
  insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, status, tenant_id)
  select id, now() + interval '2 days', now() + interval '2 days 1 hour', 2, 50, 'OPEN', 1
  from public.services limit 1
  returning id into v_slot;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000001', 'role', 'authenticated')::text, true);
  select id into v_book from public.book_slot(v_slot, true);

  -- 1. count helper: 1 active with live lock
  select public.active_booking_count(v_slot) into v_n;
  if v_n <> 1 then raise exception 'FAIL: active_booking_count must be 1'; end if;

  -- 2. engine transition + single audit row
  v_res := public.transition_booking_status(v_book, 'AWAITING_CALL', 'apply_payment');
  if v_res.status <> 'AWAITING_CALL' then raise exception 'FAIL: engine must flip status'; end if;
  if v_res.locked_until is not null then raise exception 'FAIL: engine must clear lock outside PENDING_PAYMENT'; end if;
  select count(*) into v_n from public.audit_log
    where entity_type = 'bookings' and entity_id = v_book and action = 'apply_payment';
  if v_n <> 1 then raise exception 'FAIL: exactly one audit row (no trigger double-write)'; end if;

  -- 3. no-op transition: no new audit row
  v_old_audit := v_n;
  v_res := public.transition_booking_status(v_book, 'AWAITING_CALL', 'apply_payment');
  select count(*) into v_n from public.audit_log
    where entity_type = 'bookings' and entity_id = v_book and action = 'apply_payment';
  if v_n <> v_old_audit then raise exception 'FAIL: no-op must not audit'; end if;

  -- 4. engine drops the old bookings audit trigger (single-writer proof)
  if exists (select 1 from pg_trigger where tgname = 'trg_bookings_audit' and tgrelid = 'public.bookings'::regclass)
  then raise exception 'FAIL: trg_bookings_audit must be dropped'; end if;

  -- 5. ownership gate: second user cannot touch the booking
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000002', 'role', 'authenticated')::text, true);
  begin
    v_res := public.transition_booking_status(v_book, 'CANCELLED', 'cancel_booking');
    raise exception 'FAIL: non-owner must be FORBIDDEN';
  exception when others then
    if sqlerrm not like '%FORBIDDEN%' then raise; end if;
  end;

  -- 6. parishioner cannot CONFIRM (privilege gate); admin can
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000001', 'role', 'authenticated')::text, true);
  begin
    v_res := public.transition_booking_status(v_book, 'CONFIRMED', 'confirm_booking');
    raise exception 'FAIL: parishioner must not CONFIRM';
  exception when others then
    if sqlerrm not like '%FORBIDDEN%' then raise; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000002', 'role', 'authenticated')::text, true);
  v_res := public.transition_booking_status(v_book, 'CONFIRMED', 'confirm_booking');
  if v_res.status <> 'CONFIRMED' then raise exception 'FAIL: admin must CONFIRM'; end if;

  -- 7. invalid transition still rejected by bookings_status_guard (0008)
  begin
    v_res := public.transition_booking_status(v_book, 'PENDING_PAYMENT', 'revert');
    raise exception 'FAIL: CONFIRMED->PENDING_PAYMENT must be rejected by the guard';
  exception when others then
    if sqlerrm not like '%INVALID_STATUS_TRANSITION%' then raise; end if;
  end;
  perform public.transition_booking_status(v_book, 'COMPLETED', 'complete_booking');

  -- 8. unknown booking
  begin
    v_res := public.transition_booking_status(999999999, 'CANCELLED', 'x');
    raise exception 'FAIL: unknown booking must raise';
  exception when others then
    if sqlerrm not like '%BOOKING_NOT_FOUND%' then raise; end if;
  end;

  -- 9. count helper unguarded variant + expired lock
  insert into public.bookings (slot_id, user_id, status, locked_until, created_by, tenant_id)
  values (v_slot, '00000000-0000-0000-0000-000000000002', 'PENDING_PAYMENT', now() - interval '1 minute', 'system', 1)
  returning id into v_other_book;
  select public.active_booking_count(v_slot) into v_n;
  if v_n <> 1 then raise exception 'FAIL: guarded count must skip expired lock'; end if;
  select public.active_booking_count(v_slot, true) into v_n;
  if v_n <> 2 then raise exception 'FAIL: unguarded count must include expired lock'; end if;

  raise notice 'OK';
end $$;
```

### Step 2 — migration `supabase/migrations/0024_transition_engine.sql`

```sql
-- 0024: single-writer transition engine + availability count helper.
-- Rule (conventions.md): booking status changes ONLY via transition_booking_status.
create or replace function public.active_booking_count(
  p_slot_id bigint,
  p_include_expired_locks boolean default false
) returns int language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.bookings
  where slot_id = p_slot_id
    and status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED')
    and (p_include_expired_locks
         or status <> 'PENDING_PAYMENT'
         or locked_until > now())
$$;

create or replace function public.transition_booking_status(
  p_booking_id bigint,
  p_new_status public.booking_status,
  p_action text,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
) returns public.bookings language plpgsql security definer set search_path = public as $$
declare
  v_book public.bookings;
  v_old_status public.booking_status;
  v_role text := public.current_user_role();
begin
  select * into v_book from public.bookings where id = p_booking_id for update;
  if v_book is null then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_book.status = p_new_status then return v_book; end if;

  -- SECURITY DEFINER must never widen access: re-assert gates here.
  if v_role not in ('ADMIN','PRIEST','SUPER_ADMIN') and v_book.user_id <> auth.uid()
  then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
  if p_new_status in ('CONFIRMED','COMPLETED') and v_role not in ('ADMIN','PRIEST','SUPER_ADMIN')
  then raise exception 'FORBIDDEN' using errcode = '42501'; end if;

  v_old_status := v_book.status;
  update public.bookings
     set status = p_new_status,
         locked_until = case when p_new_status = 'PENDING_PAYMENT' then locked_until else null end,
         updated_at = now()
   where id = p_booking_id
   returning * into v_book;

  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (auth.uid(), p_action, 'bookings', p_booking_id,
          jsonb_build_object('old_status', v_old_status, 'new_status', p_new_status,
                             'reason', p_reason, 'slot_id', v_book.slot_id) || p_metadata);
  return v_book;
end $$;

-- bookings audit is engine-owned now; payments + complaints triggers stay.
drop trigger if exists trg_bookings_audit on public.bookings;

grant execute on function public.transition_booking_status(bigint, public.booking_status, text, text, jsonb) to authenticated, service_role;
grant execute on function public.active_booking_count(bigint, boolean) to authenticated, service_role;
```

### Step 3 — view fix (in 0024, same migration)

`v_available_slots` (0007): replace the `active` CTE with the helper; column set otherwise identical.

```sql
drop view if exists public.v_available_slots;
create view public.v_available_slots with (security_invoker = true) as
select s.id as slot_id, s.service_id, sv.title_ar, s.starts_at, s.ends_at,
       s.capacity, s.price, s.location,
       public.active_booking_count(s.id) as booked_count,
       greatest(s.capacity - public.active_booking_count(s.id), 0) as available_seats,
       case
         when s.status = 'CLOSED' then 'CLOSED'
         when s.starts_at <= now() then 'CLOSED'
         when public.active_booking_count(s.id) >= s.capacity then 'BOOKED'
         else 'AVAILABLE'
       end as slot_status
from public.service_slots s
join public.services sv on sv.id = s.service_id
where s.tenant_id = public.tenant_id();
```

`v_schedule_today` (0004): same bug, same fix:

```sql
drop view if exists public.v_schedule_today;
create view public.v_schedule_today with (security_invoker = true) as
select sl.id as slot_id, s.title_ar, sl.starts_at, sl.ends_at, sl.location,
       case when public.active_booking_count(sl.id) > 0 then 'BOOKED' else 'AVAILABLE' end as display_status
from public.service_slots sl
join public.services s on s.id = sl.service_id
where sl.starts_at >= date_trunc('day', now())
  and sl.starts_at <  date_trunc('day', now()) + interval '1 day'
  and sl.status <> 'CLOSED'
  and sl.tenant_id = public.tenant_id()
order by sl.starts_at;
```

**Also edit (replace inline UPDATE+audit blocks with engine calls; keep behavior):**

- `0008_booking_state_machine.sql`:
  - `book_slot`: replace the `v_active` count (lines 63–66) with `select public.active_booking_count(p_slot_id) into v_active;` (guarded = exact same predicate). Keep everything else.
  - `promote_waiting_list`: replace the inline count (lines 96–98) with `if public.active_booking_count(p_slot_id, true) >= v_slot.capacity then return; end if;` (unguarded = exact same predicate). Keep its own INSERT + audit row.
  - `cancel_booking`: `select * into v_book from ... for update` → keep; replace UPDATE+audit with `v_book := public.transition_booking_status(p_booking_id, 'CANCELLED', 'cancel_booking');`; keep the waiting-list promote. (Engine re-asserts ownership, so the pre-check stays for the BOOKING_NOT_FOUND flow.)
  - `confirm_booking` / `complete_booking`: keep role gate + exists pre-check; replace UPDATE+audit with `perform public.transition_booking_status(p_booking_id, 'CONFIRMED', 'confirm_booking');` resp. `'COMPLETED'` / `'complete_booking'`.
- `0010_lock_expiry_cron.sql` — `expire_stale_bookings`: replace UPDATE+audit with `perform public.transition_booking_status(r.id, 'CANCELLED', 'expire_lock', 'stale payment lock', jsonb_build_object('slot_id', r.slot_id));`. Keep promote + cron.
- `0012_apply_payment.sql` — `apply_payment`: replace `update public.bookings set status = 'AWAITING_CALL', locked_until = null` (line 63) with `v_book := public.transition_booking_status(v_book.id, 'AWAITING_CALL', 'apply_payment', null, jsonb_build_object('payment_id', v_pay.id));`. Delete the two manual `audit_log` inserts (`auto_refund_late_webhook`, `apply_payment`) — `trg_payments_audit` captures those rows generically (single-writer rule for payments = trigger-owned). Keep refund enqueue + whatsapp enqueue (re-targeted in Task 4).
- `0015_manual_book.sql` — replace the inline count (lines 28–30) with `if public.active_booking_count(p_slot_id, true) >= v_slot.capacity then raise exception 'SLOT_TAKEN'; end if;`. Keep INSERT + audit.
- `0017_emergency_override.sql` — replace reschedule UPDATE+audit (lines 22 + 51–53 keep) with `perform public.transition_booking_status(p_booking_id, 'RESCHEDULED', 'emergency_reschedule', null, jsonb_build_object('new_slot_id', p_new_slot_id, 'refund', p_refund));`; replace the new-slot count (lines 27–29) with `if public.active_booking_count(p_new_slot_id, true) >= v_slot_new.capacity then raise exception 'NEW_SLOT_TAKEN'; end if;`. Keep new-booking INSERT + `emergency_override` audit row (create leg, engine-owned rule only covers transitions).

### Step 4 — update existing tests

- `0007_available_slots_test.sql` (and `0008`): add a parishioner-role assertion — with `request.jwt.claims` set to a parishioner (and `set local role authenticated`), `select * from v_available_slots` must show the true `booked_count`/`slot_status` of a fully booked slot (this test FAILED before the fix — the whole point of Task 1).

### Step 5 — run → PASS → commit `(backend) fix: single-writer transition engine + availability count`

---

## Task 2 — RBAC helpers

**Context:** the same role predicate is copy-pasted in ~15 policies (0002 `p0_admin_all`, 0004, 0005, 0006, 0008, 0011, 0019, 0023) and in `v_complaints` (0005). Helper functions make the matrix readable and central.

### Step 1 — failing test `supabase/tests/0025_rbac_helpers_test.sql`

```sql
-- 0025: rbac helpers
do $$
declare v_u uuid; v_p uuid; v_a uuid; v_s uuid; v_n int;
begin
  insert into public.users (id, phone, name, role, tenant_id) values
    ('00000000-0000-0000-0000-000000000011', '+201011111111', 'p', 'PARISHIONER', 1),
    ('00000000-0000-0000-0000-000000000012', '+201011111112', 'pr', 'PRIEST', 1),
    ('00000000-0000-0000-0000-000000000013', '+201011111113', 'a', 'ADMIN', 1),
    ('00000000-0000-0000-0000-000000000014', '+201011111114', 's', 'SUPER_ADMIN', 1);

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000011', 'role', 'authenticated')::text, true);
  if public.is_admin() or public.is_admin_or_priest() or public.is_super_admin()
  then raise exception 'FAIL: parishioner must be denied by all helpers'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000012', 'role', 'authenticated')::text, true);
  if public.is_admin() then raise exception 'FAIL: priest is not admin'; end if;
  if not public.is_admin_or_priest() then raise exception 'FAIL: priest is admin_or_priest'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000013', 'role', 'authenticated')::text, true);
  if not public.is_admin() then raise exception 'FAIL: admin is admin'; end if;
  if not public.is_admin_or_priest() then raise exception 'FAIL: admin is admin_or_priest'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000014', 'role', 'authenticated')::text, true);
  if not public.is_super_admin() then raise exception 'FAIL: super admin'; end if;

  -- policy smoke: parishioner cannot select service_slots (0011 + p0_admin_all); admin can
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000011', 'role', 'authenticated')::text, true);
  select count(*) into v_n from public.service_slots;
  if v_n <> 0 then raise exception 'FAIL: parishioner must not read service_slots'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000013', 'role', 'authenticated')::text, true);
  select count(*) into v_n from public.service_slots;
  if v_n = 0 then raise exception 'FAIL: admin must read service_slots'; end if;

  raise notice 'OK';
end $$;
```

### Step 2 — migration `supabase/migrations/0025_rbac_helpers.sql`

```sql
-- 0025: centralized role checks (replaces repeated current_user_role() predicates)
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.current_user_role() in ('ADMIN','SUPER_ADMIN')
$$;

create or replace function public.is_admin_or_priest()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.current_user_role() in ('ADMIN','PRIEST','SUPER_ADMIN')
$$;

create or replace function public.is_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.current_user_role() = 'SUPER_ADMIN'
$$;

grant execute on function public.is_admin() to anon, authenticated, service_role;
grant execute on function public.is_admin_or_priest() to anon, authenticated, service_role;
grant execute on function public.is_super_admin() to anon, authenticated, service_role;
```

**Also edit** — swap clauses (keep `tenant_id = public.tenant_id()` parts untouched):

- `0002_rls_baseline.sql` — `p0_admin_all` loop: `using (public.is_admin()) with check (public.is_admin())`.
- `0004_portal_read_views.sql` — `faq`/`services`/`priests` admin-write: `public.is_admin_or_priest()`.
- `0005_complaints.sql` — `v_complaints` where-clause: `(assigned_to = auth.uid() or public.is_admin()) and tenant_id = ...`; assign-write policy: `using (public.is_admin_or_priest() and tenant_id = public.tenant_id()) with check (...)`.
- `0006_announcements.sql` — admin-write: `public.is_admin_or_priest()`.
- `0008_booking_state_machine.sql` — `whatsapp_optins read own`: `... or public.is_admin()`.
- `0011_slots_rls.sql` — `service_slots admin write`: `public.is_admin_or_priest()`.
- `0019_videos.sql` — `videos admin write` (using + with check): `public.is_admin_or_priest()`.
- `0023_analytics_views.sql` — three `p_analytics_read_admin` policies: `using (public.is_admin_or_priest())`.

### Step 3 — run → PASS → commit `(backend) fix: centralize RBAC role checks`

---

## Task 3 — Complaints crypto in-DB

**Context:** `complaints.body_encrypted` is `bytea` (0001/0005), never readable via PostgREST (deny-select policy + views without body). Encryption currently happens in `complaints-encrypt`/`complaints-decrypt` edge functions. Move into Postgres with pgcrypto + Vault key `COMPLAINTS_KEY`; delete both edge functions.

### Step 1 — failing test `supabase/tests/0026_complaints_crypto_test.sql`

```sql
-- 0026: complaints pgp round-trip + access rules
do $$
declare v_u uuid; v_a uuid; v_cid bigint; v_body text; v_enc bytea; v_role text;
begin
  insert into public.users (id, phone, name, role, tenant_id) values
    ('00000000-0000-0000-0000-000000000021', '+201022222221', 'c', 'PARISHIONER', 1),
    ('00000000-0000-0000-0000-000000000022', '+201022222222', 'c2', 'PARISHIONER', 1),
    ('00000000-0000-0000-0000-000000000023', '+201022222223', 'a', 'ADMIN', 1);

  -- vault key (test-scoped; dev key ships in seed — see Step 2)
  insert into vault.secrets (name, secret) values ('COMPLAINTS_KEY', 'test-complaints-key')
  on conflict (name) do update set secret = excluded.secret;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000021', 'role', 'authenticated')::text, true);
  select public.submit_complaint_secure('feedback', 'body-plaintext') into v_cid;
  if v_cid is null then raise exception 'FAIL: submit must return id'; end if;

  select body_encrypted into v_enc from public.complaints where id = v_cid;
  if v_enc = convert_to('body-plaintext', 'UTF8') then raise exception 'FAIL: body must be encrypted at rest'; end if;

  -- round-trip for owner
  select public.decrypt_complaint(v_cid) into v_body;
  if v_body <> 'body-plaintext' then raise exception 'FAIL: decrypt round-trip'; end if;

  -- other parishioner: FORBIDDEN
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000022', 'role', 'authenticated')::text, true);
  begin
    v_body := public.decrypt_complaint(v_cid);
    raise exception 'FAIL: other user must be FORBIDDEN';
  exception when others then
    if sqlerrm not like '%FORBIDDEN%' then raise; end if;
  end;

  -- admin decrypts any
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000023', 'role', 'authenticated')::text, true);
  select public.decrypt_complaint(v_cid) into v_body;
  if v_body <> 'body-plaintext' then raise exception 'FAIL: admin decrypt'; end if;

  -- missing key -> COMPLAINTS_KEY_NOT_SET
  delete from vault.secrets where name = 'COMPLAINTS_KEY';
  begin
    v_body := public.decrypt_complaint(v_cid);
    raise exception 'FAIL: missing key must raise';
  exception when others then
    if sqlerrm not like '%COMPLAINTS_KEY_NOT_SET%' then raise; end if;
  end;
  insert into vault.secrets (name, secret) values ('COMPLAINTS_KEY', 'test-complaints-key')
  on conflict (name) do update set secret = excluded.secret;

  raise notice 'OK';
end $$;
```

### Step 2 — migration `supabase/migrations/0026_complaints_pgcrypto.sql`

```sql
-- 0026: complaints crypto in-DB (replaces complaints-encrypt/decrypt edge functions)
create or replace function public.submit_complaint_secure(p_category text, p_body text)
returns bigint language plpgsql security definer set search_path = public, extensions as $$
declare
  v_user uuid := auth.uid();
  v_key text;
  v_id bigint;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED' using errcode = '28000'; end if;
  if p_category is null or p_body is null or length(p_body) > 4000
  then raise exception 'BAD_REQUEST'; end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'COMPLAINTS_KEY' limit 1;
  if v_key is null then raise exception 'COMPLAINTS_KEY_NOT_SET'; end if;
  insert into public.complaints (user_id, category, body_encrypted, tenant_id)
  values (v_user, p_category, pgp_sym_encrypt(p_body, v_key), public.tenant_id())
  returning id into v_id;
  -- audit: complaints trigger (trg_complaints_audit) owns the row; nothing manual (single-writer rule)
  return v_id;
end $$;

create or replace function public.decrypt_complaint(p_complaint_id bigint)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  v_role text := public.current_user_role();
  v_row public.complaints;
  v_key text;
begin
  select * into v_row from public.complaints where id = p_complaint_id;
  if v_row is null then raise exception 'COMPLAINT_NOT_FOUND'; end if;
  -- mirror v_complaints (0005): admin/super, or the assigned user (priest only when assigned)
  if v_role not in ('ADMIN','SUPER_ADMIN') and v_row.assigned_to <> auth.uid()
  then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'COMPLAINTS_KEY' limit 1;
  if v_key is null then raise exception 'COMPLAINTS_KEY_NOT_SET'; end if;
  return pgp_sym_decrypt(v_row.body_encrypted, v_key)::text;
end $$;

grant execute on function public.submit_complaint_secure(text, text) to authenticated;
grant execute on function public.decrypt_complaint(bigint) to authenticated, service_role;

-- dev key for local stack (production sets it in the dashboard once, per conventions)
insert into vault.secrets (name, secret) values ('COMPLAINTS_KEY', 'dev-only-complaints-key')
on conflict (name) do nothing;
```

**Delete:** `supabase/functions/complaints-encrypt/`, `supabase/functions/complaints-decrypt/` (index.ts + tests). Update master plan §Edge Functions + conventions.md §Complaints: "AES-GCM via edge fn" → "pgp_sym_encrypt in-DB, Vault key COMPLAINTS_KEY".

### Step 3 — run → PASS → commit `(backend) fix: complaints crypto in-DB`

---

## Task 4 — Unified outbox + event dispatcher

**Context:** `whatsapp_outbox` drained by `whatsapp-sender` (cron 0016), `refund_requests` drained by `paymob-refund` (cron 0018). Both drain loops move into one `event-dispatcher` over `event_outbox`. Enqueue sites: 0012 (apply_payment), 0017 (emergency_override), 0019 (apply_video_payment). Template names are constrained by 0014: `booking_confirmed, payment_received, booking_cancelled, booking_rescheduled, booking_apology, otp_auth, booking_payment_received, booking_offer` (there is **no** `video_purchased` — 0019 uses `payment_received` with `link` param).

**New enums (0001 back-propagation):** add guarded, after the `complaint_status` block in `0001_init_schema.sql`:

```sql
if not exists (select 1 from pg_type where typname = 'event_handler_type') then
  create type public.event_handler_type as enum ('WHATSAPP','PAYMOB_REFUND','FCM_PUSH','SMS');
end if;
if not exists (select 1 from pg_type where typname = 'outbox_status') then
  create type public.outbox_status as enum ('PENDING','PROCESSING','SENT','FAILED');
end if;
```

### Step 1 — failing test `supabase/tests/0027_event_outbox_test.sql`

```sql
-- 0027: event_outbox schema + enqueue behavior
do $$
declare v_user uuid; v_slot bigint; v_book bigint; v_pay bigint; v_n int;
begin
  insert into public.users (id, phone, name, role, tenant_id)
  values ('00000000-0000-0000-0000-000000000031', '+201033333331', 'p', 'PARISHIONER', 1);
  insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, status, tenant_id)
  select id, now() + interval '2 days', now() + interval '2 days 1 hour', 1, 50, 'OPEN', 1
  from public.services limit 1
  returning id into v_slot;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000031', 'role', 'authenticated')::text, true);
  select id into v_book from public.book_slot(v_slot, true);

  -- 1. apply_payment enqueues WHATSAPP booking_payment_received
  insert into public.payments (booking_id, amount, status, tenant_id)
  values (v_book, 50, 'CREATED', 1) returning id into v_pay;
  perform public.apply_payment(v_pay);
  select count(*) into v_n from public.event_outbox
    where handler_type = 'WHATSAPP' and payload->>'template_name' = 'booking_payment_received';
  if v_n <> 1 then raise exception 'FAIL: apply_payment must enqueue WHATSAPP event'; end if;
  if (select status from public.event_outbox limit 1) <> 'PENDING' then raise exception 'FAIL: default PENDING'; end if;

  -- 2. old tables gone
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename in ('whatsapp_outbox','refund_requests'))
  then raise exception 'FAIL: legacy outbox tables must be dropped'; end if;

  -- 3. RLS: clients cannot read or write event_outbox (no policies)
  select count(*) into v_n from public.event_outbox;
  if v_n <> 0 then raise exception 'FAIL: clients must not read event_outbox'; end if;
  begin
    insert into public.event_outbox (handler_type, payload) values ('WHATSAPP', '{}'::jsonb);
    raise exception 'FAIL: client insert must be blocked';
  exception when others then null; end;

  raise notice 'OK';
end $$;
```

### Step 2 — migration `supabase/migrations/0027_event_outbox.sql`

```sql
-- 0027: unified event outbox (replaces whatsapp_outbox + refund_requests + 2 crons)
create table public.event_outbox (
  id bigint generated always as identity primary key,
  tenant_id bigint not null default public.tenant_id(),
  handler_type public.event_handler_type not null,
  payload jsonb not null default '{}'::jsonb,
  status public.outbox_status not null default 'PENDING',
  attempts int not null default 0 check (attempts between 0 and 5),
  next_attempt_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint event_outbox_whatsapp_template_check check (
    handler_type <> 'WHATSAPP'
    or payload->>'template_name' in ('booking_confirmed','payment_received','booking_cancelled',
                                    'booking_rescheduled','booking_apology','otp_auth',
                                    'booking_payment_received','booking_offer')
  )
);
alter table public.event_outbox enable row level security;
-- no policies: only SECURITY DEFINER RPCs (enqueue) and the dispatcher (service role) touch it.

create index idx_event_outbox_drain on public.event_outbox (status, next_attempt_at)
  where status = 'PENDING';

-- migrate queued rows (deployed DBs; fresh resets start empty)
insert into public.event_outbox (tenant_id, handler_type, payload, status, attempts, next_attempt_at, created_at)
select coalesce(o.tenant_id, 1), 'WHATSAPP',
       jsonb_build_object('phone', o.phone, 'template_name', o.template_name, 'params', o.params),
       o.status::text::public.outbox_status, o.attempts, o.next_attempt_at, o.created_at
from public.whatsapp_outbox o;
insert into public.event_outbox (tenant_id, handler_type, payload, status, attempts, next_attempt_at, created_at)
select 1, 'PAYMOB_REFUND',
       jsonb_build_object('payment_id', r.payment_id, 'amount', r.amount),
       'PENDING', r.attempts, r.next_attempt_at, r.created_at
from public.refund_requests r;

drop table public.whatsapp_outbox;
drop table public.refund_requests;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'whatsapp-sender') then
    perform cron.unschedule('whatsapp-sender');
  end if;
  if exists (select 1 from cron.job where jobname = 'refund-drain') then
    perform cron.unschedule('refund-drain');
  end if;
end $$;
```

(`whatsapp_outbox.status` legacy values PENDING/SENT/FAILED are valid `outbox_status` casts; 0014 never allowed PROCESSING.)

### Step 3 — edit enqueue sites (same migration file edits)

- `0012_apply_payment.sql` — replace the `whatsapp_outbox` insert (lines 64–72) with:
  ```sql
  if v_phone is not null and not exists (
    select 1 from public.event_outbox
    where payload->>'booking_id' = v_book.id::text and payload->>'template_name' = 'booking_payment_received'
  ) then
    insert into public.event_outbox (handler_type, payload)
    values ('WHATSAPP', jsonb_build_object('phone', v_phone, 'template_name', 'booking_payment_received',
                                           'params', jsonb_build_object('booking_id', v_book.id, 'amount', v_pay.amount)));
  end if;
  ```
  and the `refund_requests` insert (lines 56–57) with:
  ```sql
  insert into public.event_outbox (handler_type, payload)
  values ('PAYMOB_REFUND', jsonb_build_object('payment_id', v_pay.id, 'amount', v_pay.amount))
  on conflict do nothing;
  ```
  (`on conflict do nothing` — dedupe: legacy used `uq_refund_requests_payment` + conflict; event_outbox has no unique key on payload, so add a guard: keep it idempotent via `not exists` check or accept the cron-level `PROCESSING` in-flight window. Use the legacy `not exists` pattern above for WhatsApp; for refunds, wrap in `if not exists (select 1 from public.event_outbox where handler_type='PAYMOB_REFUND' and payload->>'payment_id' = v_pay.id::text)`.)
- `0017_emergency_override.sql` — the two `whatsapp_outbox` inserts → `event_outbox` rows with `params` preserved (`booking_apology` params `{booking_id}`; `booking_rescheduled` params `{old_slot, new_slot}`); the `refund_requests` insert (lines 45–49) → one `PAYMOB_REFUND` row per payment (`payment_id`, `amount`).
- `0019_videos.sql` — `apply_video_payment` whatsapp insert (lines 100–107) → `event_outbox` with `template_name = 'payment_received'`, params `{link: yt_url}`, same `not exists` dedupe on `payload->>'link'` + `phone`.
- `0014_whatsapp_queue.sql` — delete everything except the `whatsapp_optins_source_check` constraint block (the outbox constraints moved to 0027's table + `event_outbox_whatsapp_template_check`).
- `0016_whatsapp_sender_cron.sql` — rewrite to schedule the dispatcher (0013 pattern):
  ```sql
  select cron.schedule('event-dispatcher', '* * * * *', $$
    select net.http_post(
      url := 'https://' || (select decrypted_secret from vault.decrypted_secrets where name = 'SUPABASE_URL' limit 1)
         || '/functions/v1/event-dispatcher',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'SERVICE_ROLE_KEY' limit 1),
        'Content-Type', 'application/json'),
      body := '{}');
  $$);
  ```
- **Delete** `0018_refund_cron.sql`, `supabase/functions/whatsapp-sender/`, `supabase/functions/paymob-refund/`.

### Step 4 — edge function `supabase/functions/event-dispatcher/index.ts`

Port of both drains (whatsapp-sender templates/opt-in/ar/v20.0/backoff 30s·2ⁿ/max 5; paymob-refund auth-token → refund → `payments.status='REFUNDED'`, max 3, no backoff). Deps injected; same shape as the existing functions.

```ts
import { createClient } from "npm:@supabase/supabase-js@2";

export const TEMPLATES: Record<string, { paramCount: number }> = {
  booking_confirmed: { paramCount: 1 },
  payment_received: { paramCount: 1 },
  booking_cancelled: { paramCount: 0 },
  booking_rescheduled: { paramCount: 2 },
  booking_apology: { paramCount: 1 },
  otp_auth: { paramCount: 1 },
  booking_payment_received: { paramCount: 2 },
  booking_offer: { paramCount: 1 },
};
export const MAX_ATTEMPTS = 5;
export const REFUND_MAX_ATTEMPTS = 3;
export const BACKOFF_MS = 30_000;
export const DRAIN_BATCH = 10;
export const DRAIN_LIMIT = 100;

export interface Deps {
  getClient(): ReturnType<typeof createClient>;
  fetch: typeof fetch;
  phoneId: string;
  paymobApiKey: string;
  amountMultiplier: number;
}

type Row = { id: number; handler_type: string; payload: Record<string, unknown>; attempts: number };
type Result = { ok: boolean; retryable: boolean };

async function setStatus(client: ReturnType<typeof createClient>, id: number, status: string, extra: Record<string, unknown> = {}) {
  await client.from("event_outbox").update({ status, ...extra }).eq("id", id);
}

export async function sendWhatsApp(row: Row, deps: Deps): Promise<Result> {
  const client = deps.getClient();
  const { phone, template_name, params } = row.payload as { phone?: string; template_name?: string; params?: Record<string, unknown> };
  if (!phone || !template_name) return { ok: false, retryable: false };
  const tmpl = TEMPLATES[template_name];
  if (!tmpl) return { ok: false, retryable: false };
  const { data: optin } = await client.from("whatsapp_optins").select("phone").eq("phone", phone).maybeSingle();
  if (!optin) return { ok: false, retryable: false };
  const bodyParams = Array.from({ length: tmpl.paramCount }, (_, idx) => ({
    type: "text", text: String(Object.values(params ?? {})[idx] ?? ""),
  }));
  const res = await deps.fetch(`https://graph.facebook.com/v20.0/${deps.phoneId}/messages`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${Deno.env.get("WHATSAPP_TOKEN")}` },
    body: JSON.stringify({
      messaging_product: "whatsapp", to: phone, type: "template",
      template: { name: template_name, language: { code: "ar" }, components: [{ type: "body", parameters: bodyParams }] },
    }),
  });
  if (res.ok) return { ok: true, retryable: false };
  return res.status >= 400 && res.status < 500 ? { ok: false, retryable: false } : { ok: false, retryable: true };
}

export async function triggerPaymobRefund(row: Row, deps: Deps): Promise<Result> {
  const client = deps.getClient();
  const { payment_id, amount } = row.payload as { payment_id?: number; amount?: number };
  if (!payment_id || !amount) return { ok: false, retryable: false };
  const { data: pay } = await client.from("payments").select("gateway_ref").eq("id", payment_id).single();
  if (!pay?.gateway_ref) return { ok: false, retryable: false };
  const authRes = await deps.fetch("https://accept.paymob.com/api/auth/tokens", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ api_key: deps.paymobApiKey }),
  });
  const authJson = (await authRes.json()) as Record<string, unknown>;
  const res = await deps.fetch("https://accept.paymob.com/api/acceptance/void_refund/refund", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ auth_token: String(authJson.token ?? ""), transaction_id: pay.gateway_ref, amount_cents: Math.round(Number(amount) * deps.amountMultiplier) }),
  });
  if (res.ok) {
    await client.from("payments").update({ status: "REFUNDED" }).eq("id", payment_id);
    return { ok: true, retryable: false };
  }
  return res.status >= 400 && res.status < 500 ? { ok: false, retryable: false } : { ok: false, retryable: true };
}

const HANDLERS: Record<string, (row: Row, deps: Deps) => Promise<Result>> = {
  WHATSAPP: sendWhatsApp,
  PAYMOB_REFUND: triggerPaymobRefund,
};

export async function handleRequest(_req: Request, deps: Deps): Promise<Response> {
  const cors = { "Access-Control-Allow-Origin": "*" };
  try {
    const client = deps.getClient();
    const { data: queue, error } = await client.from("event_outbox")
      .select("id, handler_type, payload, attempts")
      .eq("status", "PENDING").lte("next_attempt_at", new Date().toISOString())
      .order("created_at", { ascending: true }).limit(DRAIN_LIMIT);
    if (error) throw error;
    let handled = 0;
    const rows = queue ?? [];
    for (let i = 0; i < rows.length; i += DRAIN_BATCH) {
      const results = await Promise.all(rows.slice(i, i + DRAIN_BATCH).map(async (row) => {
        const handler = HANDLERS[row.handler_type];
        if (!handler) { await setStatus(client, row.id, "FAILED"); return 0; }
        await setStatus(client, row.id, "PROCESSING");
        const outcome = await handler(row as Row, deps);
        if (outcome.ok) { await setStatus(client, row.id, "SENT"); return 1; }
        if (!outcome.retryable) { await setStatus(client, row.id, "FAILED"); return 0; }
        const attempts = row.attempts + 1;
        if (attempts >= (row.handler_type === "PAYMOB_REFUND" ? REFUND_MAX_ATTEMPTS : MAX_ATTEMPTS)) {
          await setStatus(client, row.id, "FAILED");
        } else {
          const backoff = row.handler_type === "PAYMOB_REFUND" ? 0 : BACKOFF_MS * Math.pow(2, attempts);
          await setStatus(client, row.id, "PENDING", { attempts, next_attempt_at: new Date(Date.now() + backoff).toISOString() });
        }
        return 0;
      }));
      handled += results.reduce((a, b) => a + b, 0);
    }
    return new Response(JSON.stringify({ ok: true, handled }), { status: 200, headers: cors });
  } catch (e) {
    console.error("event-dispatcher error", e);
    return new Response(JSON.stringify({ error: "INTERNAL" }), { status: 500, headers: cors });
  }
}

if (typeof Deno !== "undefined" && Deno.serve) {
  Deno.serve((req) => handleRequest(req, {
    getClient: () => createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } }),
    fetch, phoneId: Deno.env.get("WHATSAPP_PHONE_ID")!, paymobApiKey: Deno.env.get("PAYMOB_API_KEY")!, amountMultiplier: 100,
  }));
}
```

### Step 5 — dispatcher tests + e2e update

- `supabase/functions/event-dispatcher/index_test.ts` — port `whatsapp-sender`'s test file (same fake-client stubbing — see `supabase/functions/_shared/fake_supabase.ts`) onto `event_outbox` rows `{handler_type, payload}`: template param order (`booking_payment_received` → booking_id, amount), no-opt-in → FAILED, unknown template → FAILED, unknown handler → FAILED, 5xx → backoff `PENDING` with `attempts+1` and `next_attempt_at > now`, 4xx → FAILED, 500-sim on `getClient` → 500 response. Add refund tests: PAYMOB_REFUND row → auth-token POST then refund POST with `amount_cents = amount*100`, success sets payments REFUNDED + event SENT; 4xx → FAILED; missing gateway_ref → FAILED; attempt cap 3 for refunds.
- Update `0014_whatsapp_queue_test.sql` → asserts against `event_outbox` + `cron.job` names (`event-dispatcher` present, `whatsapp-sender`/`refund-drain` absent); update `0016_whatsapp_cron_test.sql` (now dispatcher cron). `0017_emergency_override_test.sql` / `0012_apply_payment_test.sql` — swap `whatsapp_outbox`/`refund_requests` asserts to `event_outbox` (`payload->>'template_name'`, `payload->>'payment_id'`).
- e2e `supabase/e2e/book_pay_flow.mjs` — outbox asserts (lines ~62–71) become:
  ```js
  const { data: outbox } = await service.from("event_outbox")
    .select("handler_type, payload, status").eq("payload->>phone", user.phone).order("created_at", { ascending: true });
  const names = outbox.map((r) => r.payload.template_name);
  assert(names.includes("booking_payment_received"), "booking_payment_received missing");
  assert(names.includes("booking_confirmed"), "booking_confirmed missing");
  assert(outbox.every((r) => r.handler_type === "WHATSAPP" && r.status === "PENDING"), "events PENDING until dispatcher runs");
  ```

### Step 6 — run all → PASS → commit `(backend) fix: unified event_outbox + event-dispatcher`

---

## Task 5 — Edge-function seam hygiene

**Context:** `whatsapp-sender`/`paymob-refund`/`paymob-checkout`/`paymob-webhook`/`reconcile-payments`/`youtube-expiry` already use the injected-deps pattern (`handleRequest(req, deps)` + thin `Deno.serve`) — only the `createClient(...)` call is duplicated in each bootstrap. `analytics-export` is the outlier: it builds both clients **inside** the handler and has no deps seam (also the CSV formula-injection guard `esc()` already exists — keep it). `_shared/` currently has only `fake_supabase.ts`.

### Step 1 — failing test first: `supabase/functions/analytics-export/index_test.ts`

Refactor its existing tests to inject deps; add:
- garbage `Authorization` token → 401 (stub `getUser` → `{ data: { user: null }, error: null }`);
- no token → 401;
- role `PARISHIONER` → 403 (stub role select);
- role `PRIEST` → 200 CSV (PRIEST allowed, matching `exportAllowed`);
- non-GET → 405; unknown report → 400.

### Step 2 — `supabase/functions/_shared/client.ts`

```ts
import { createClient } from "npm:@supabase/supabase-js@2";

export function makeServiceClient(url: string | undefined, key: string | undefined) {
  return createClient(url ?? "", key ?? "", { auth: { persistSession: false } });
}
export function makeAnonClient(url: string | undefined, key: string | undefined) {
  return createClient(url ?? "", key ?? "", { auth: { persistSession: false } });
}
```

### Step 3 — `analytics-export/index.ts` rewrite (behavior identical)

```ts
import type { SupabaseClient, User } from "npm:@supabase/supabase-js@2";

export interface Deps {
  getServiceClient(): SupabaseClient;
  getAnonClient(): SupabaseClient;
  getUser(token: string): Promise<{ data: { user: User | null }; error: unknown }>;
}

export function buildCsv(headers: string[], rows: string[][]): string {
  const esc = (v: string) => {
    const s = /^[=+\-@]/.test(v) ? "'" + v : v;
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return "\uFEFF" + [headers.map(esc).join(","), ...rows.map((r) => r.map(esc).join(","))].join("\n") + "\n";
}

export function exportAllowed(role: string | undefined): boolean {
  return role === "PRIEST" || role === "ADMIN" || role === "SUPER_ADMIN";
}

export async function handleRequest(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== "GET") return new Response("method not allowed", { status: 405 });
  const url = new URL(req.url);
  const report = url.searchParams.get("report") ?? "";
  const month = url.searchParams.get("month") ?? "";
  if (!["utilization", "payments", "bookings"].includes(report)) {
    return new Response("unknown report", { status: 400 });
  }
  const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  const { data: { user }, error } = await deps.getUser(token);
  if (error || !user) return new Response("unauthorized", { status: 401 });
  const { data: profile } = await deps.getAnonClient().from("users").select("role").eq("id", user.id).single();
  if (!exportAllowed(profile?.role as string | undefined)) return new Response("forbidden", { status: 403 });

  const viewMap: Record<string, string> = {
    utilization: "v_analytics_utilization",
    payments: "v_analytics_payments",
    bookings: "v_analytics_bookings",
  };
  let query = deps.getServiceClient().from(viewMap[report]).select("*");
  if (month) query = query.eq("month", month);
  const { data, error: qErr } = await query;
  if (qErr) return new Response(qErr.message, { status: 500 });
  const rows = (data ?? []).map((r: Record<string, unknown>) => Object.values(r).map(String));
  const headers = data && data.length > 0 ? Object.keys(data[0]) : ["empty"];
  return new Response(buildCsv(headers, rows), {
    headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": `attachment; filename="${report}-${month}.csv"` },
  });
}

if (typeof Deno !== "undefined" && Deno.serve) {
  Deno.serve((req) => handleRequest(req, {
    getServiceClient: () => makeServiceClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")),
    getAnonClient: () => makeAnonClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_ANON_KEY")),
    getUser: async (token) => makeAnonClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_ANON_KEY")).auth.getUser(token),
  }));
}
```

### Step 4 — serve() closures use the factory

`paymob-checkout`, `paymob-webhook`, `reconcile-payments`, `youtube-expiry`: replace their inline `createClient(...)` with `makeServiceClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"))` (and `makeAnonClient` where they use the anon key — verify per file). No behavior change; existing per-function tests must stay green.

### Step 5 — run all deno tests → PASS → commit `(backend) fix: shared client factory + analytics-export deps`

---

## Verification checklist (before handoff)

- `psql ... -f supabase/tests/run_all.sql` (updated) → no output, exit 0
- `npx supabase db reset` on a clean stack → all migrations (0001–0027) apply; cron jobs: `expire-bookings`, `event-dispatcher`, `reconcile-payments`, `youtube-expiry`, `analytics-nightly`
- `deno test --allow-env supabase/functions/event-dispatcher/` + all other function dirs → PASS
- e2e `node supabase/e2e/book_pay_flow.mjs` → PASS
- Greps zero: `whatsapp_outbox|refund_requests|whatsapp-sender|paymob-refund|trg_bookings_audit|complaints-encrypt|complaints-decrypt` (outside git history)
- Role-predicate duplication: only in 0002/0025 helpers + `current_user_role()` call sites
- Enum sync (checklist 1): `event_handler_type` + `outbox_status` in `conventions.md` §Enums, `0001_init_schema.sql`, `0027_event_outbox.sql`
- Conventions + master plan updated: §Outbox pattern → event_outbox; §Audit → single-writer rule; §Complaints → pgp in-DB; master §5 schema list + §Edge Functions table (event-dispatcher, in-DB complaints); §6 state machine unchanged (no booking status added)

## Risks / notes

- `transition_booking_status` is SECURITY DEFINER: the FOR UPDATE + re-asserted gates + single audit insert must never be split up. Add the "bookings status changes ONLY via transition_booking_status" rule to `conventions.md` (checklist-style line in §Audit).
- Keep `bookings_status_guard` (0008) — engine relies on it for transition validation.
- `v_available_slots`/`v_schedule_today` now call `active_booking_count` twice per row — trivial cost at church scale (≤ hundreds of slots), fine for phase 1; note it in conventions if it ever shows up in EXPLAIN.
- `event_outbox` has no client policies on purpose (all enqueues are SECURITY DEFINER). If a client-initiated send is ever needed, add a narrow `with check` policy — deliberately not done now.
- The analysis doc's divergences (tenants table, service_settings, etc.) are NOT in this plan; if they represent a future multi-tenant phase, write a separate plan against real migrations.
