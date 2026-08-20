# Phase 1 Data Model: Schema Integrity Fixes

This feature adds no tables, no columns that carry user data, and no new user-facing surface. It changes what
the existing schema will accept. The deltas below are grouped by migration so each can be reviewed and
reverted as an independent unit.

Every "current state" line was read from the live database (`supabase_db_church`, migrations applied through
`0054`) via `pg_constraint`, `pg_policies`, `pg_type`, and `information_schema` — not from the Studio
visualizer export, which omits all `ON DELETE` clauses.

## `0055` — vault preflight

### New function: `public.vault_preflight()`

Reports which required secrets are absent from `vault.decrypted_secrets`.

| Property | Value |
|----------|-------|
| Returns | `setof text` — the name of each missing secret |
| Volatility | `stable` |
| Security | `security definer`, `set search_path to ''` |
| Required names | `COMPLAINTS_KEY`, `SUPABASE_URL`, `SERVICE_ROLE_KEY` |
| Grants | `authenticated` is not granted. The gate script and deploy tooling call it as the service role |

The function returns names, never values. A missing secret must be reported by name so the operator knows
which one to provision; a present secret's contents must never appear in output or logs.

## `0056` — `handle_new_user` hardening

### Changed function: `public.handle_new_user()`

| | Behavior |
|---|---|
| Current | `values (new.id, coalesce(nullif(new.phone, ''), new.id::text), ...)` — a signup with no phone silently receives its own UUID as its phone number |
| Target | The UUID fallback is removed. A signup with no phone number raises rather than inserting a synthetic value |

The trigger keeps `security definer`, `set search_path to ''`, fully qualified writes, and
`on conflict (id) do nothing`. Only the fallback expression changes.

Raising here is deliberate: it turns a silently-created junk account into a visible failure. Combined with
`enable_signup = false` in `config.toml`, the phone-OTP path becomes the only way an account can exist.

## `0057` — integrity constraints

All constraints are added and validated in a single step. Every violating-row count measured against live data
is zero (see `research.md`), so no data repair precedes them.

| Table | Constraint | Definition | Current state |
|-------|-----------|------------|---------------|
| `service_slots` | `service_slots_time_order_chk` | `CHECK (ends_at > starts_at)` | Absent. Only the nullable `schedule_range` was guarded, so a slot with a null range had no ordering guarantee |
| `service_slots` | `service_slots_capacity_nonneg_chk` | `CHECK (capacity >= 0)` | Absent |
| `service_slots` | `service_slots_price_nonneg_chk` | `CHECK (price >= 0)` | Absent |
| `bookings` | `bookings_seat_count_min_chk` | `CHECK (seat_count >= 1)` | Absent. Zero or negative breaks capacity arithmetic in `book_slot` and `active_booking_count` |
| `payments` | `payments_amount_nonneg_chk` | `CHECK (amount >= 0)` | Absent, while `bookings.paid_amount` already carries exactly this check |
| `media_assets` | `media_assets_polymorphic_chk` | `CHECK ((content_type IS NULL) = (content_id IS NULL))` | Absent. Either half of the polymorphic pair could be set alone |

### Constraint dropped

| Table | Constraint | Reason |
|-------|-----------|--------|
| `bookings` | the `status` CHECK re-listing all six `booking_status` values | Redundant with the enum, and it must be edited every time the enum grows. Dropping it leaves the enum as the single source of truth |

Note that `ends_at > starts_at` is strict, not `>=`. A zero-length slot is not a valid bookable window, and no
existing row relies on one.

## `0058` — status enums

Two enums are created with exactly the values in use. No lifecycle values are invented; the genuine gap in the
waiting-list lifecycle is recorded as an open question in `research.md` rather than guessed at here.

| Enum | Values | Replaces |
|------|--------|----------|
| `slot_status` | `OPEN`, `CLOSED` | `service_slots.status text` |
| `waitlist_status` | `WAITING`, `OFFERED` | `waiting_list.status text` |

### Conversion facts

| Column | Live data | Writers | Readers to re-verify |
|--------|-----------|---------|---------------------|
| `service_slots.status` | `OPEN` only | `apps/admin/lib/features/slots/slots_admin_screen.dart:37` writes the string `'CLOSED'` through PostgREST, which Postgres casts to the enum. No SQL writes it | `0008`, `0015`, `0017`, `0028`, `0048`, `0053` |
| `waiting_list.status` | Empty table | `promote_waiting_list` writes `OFFERED` at `0008_booking_state_machine.sql:99`; `WAITING` is the column default | `0008_booking_state_machine.sql:89,117` |

Both conversions preserve the existing default. Every comparison site listed above must be confirmed to still
resolve after conversion — a comparison against an unquoted literal will resolve against the enum, but a
comparison that had been relying on text semantics would not.

### Dependent views

Two views must be dropped and recreated inside this migration. Postgres refuses `ALTER COLUMN ... TYPE` while a
view depends on the column.

| View | Defined at | References |
|------|-----------|-----------|
| `v_available_slots` | `supabase/migrations/0024_transition_engine.sql:62` | `s.status = 'CLOSED'` inside a CASE |
| `v_schedule_today` | `supabase/migrations/0024_transition_engine.sql:78` | `sl.status <> 'CLOSED'` in its WHERE clause |

Recreating a view drops its grants. `supabase/migrations/0050_explicit_read_grants.sql:63-64` grants `SELECT` on
both to `anon, authenticated`, so this migration must restore them. Omitting the re-grant silently removes the
mobile app's slot listing — the view still exists and still works for the service role, so nothing errors.

No view depends on `waiting_list.status`.

## `0059` — tenant scaffolding

Scope is making the scaffolding self-consistent with the pattern every other table already follows.
Constitution line 22 ratifies single-church deployment, so none of these can fire today. No tenant-isolation
test suite is in scope.

### `payments_monthly`

| | Current | Target |
|---|---------|--------|
| Primary key | `(month)` | `(tenant_id, month)` |

It is the only rollup with no tenant-scoping key — `bookings_monthly` and `slot_utilization_monthly` both key
on the tenant-scoped `service_id`. The table holds zero rows and is fully rebuilt by `materialize_analytics`,
so the change is lossless.

### Changed function: `public.materialize_analytics()`

| | Current | Target |
|---|---------|--------|
| Delete | `DELETE FROM public.payments_monthly WHERE month = m` | Adds a `tenant_id` predicate |
| Insert | `INSERT INTO public.payments_monthly (month, total_paid, total_refunded, count_paid)` | Includes `tenant_id` |

Idempotency is the property under test: two consecutive runs must produce identical rollups.

### `audit_log`

| | Current | Target |
|---|---------|--------|
| `tenant_id` | Column does not exist | `bigint NOT NULL DEFAULT tenant_id()` |
| Policy | bare `USING is_admin()` | `is_admin()` plus a tenant predicate |

The table holds zero rows, so `NOT NULL` needs no backfill.

### `whatsapp_optins`

| | Current | Target |
|---|---------|--------|
| Primary key | `(phone)` | `(tenant_id, phone)` |
| `tenant_id` | Nullable, no default — the only table in the schema like this | `NOT NULL DEFAULT tenant_id()` |
| Policy | No tenant predicate | Tenant predicate added |

Unlike the other two tables, this one may hold rows. `research.md` measured `wa_null_tenant=0`, so the
`NOT NULL` is safe against current local data, but the count must be re-measured before this migration is
applied to production.

## `0060` — remove the priest abstraction

### Function dropped: `public.is_admin_or_priest()`

Its body is exactly `select public.is_admin()`. `app_role` is `(USER, ADMIN, SUPER_ADMIN)` — there is no
`PRIEST` value, and `priests` has no foreign key to `users`, so a priest row cannot be linked to the account it
would represent. The substitution is therefore behavior-preserving.

### Eight policies recreated first

Read from `pg_policies`, not from migration history, since later migrations supersede earlier ones.

| Table | Policy | Command |
|-------|--------|---------|
| `announcements` | `announcements admin write` | `ALL` |
| `faq` | `faq admin write` | `ALL` |
| `priests` | `priests admin write` | `ALL` |
| `service_slots` | `service_slots admin write` | `ALL` |
| `services` | `services admin write` | `ALL` |
| `bookings_monthly` | `p_analytics_read_admin` | `SELECT` |
| `payments_monthly` | `p_analytics_read_admin` | `SELECT` |
| `slot_utilization_monthly` | `p_analytics_read_admin` | `SELECT` |

Ordering is load-bearing. Recreate all eight against `is_admin()`, then
`DROP FUNCTION public.is_admin_or_priest()` **without** `CASCADE`. `CASCADE` would drop the eight policies
themselves, removing access control from eight tables while the migration appeared to succeed.

### Test file deleted

`supabase/tests/0005_priest_self_assign_test.sql` tests a role that does not exist. It is deleted and
deregistered from `run_all.sql`.

## `0061` — user delete semantics

Four foreign keys into `users` currently have `NO ACTION`, while `auth.users` → `public.users` is
`ON DELETE CASCADE`. The cascade promises a hard delete that then aborts against these keys for any user who
has ever booked.

| Table | Column | Current | Target |
|-------|--------|---------|--------|
| `bookings` | `user_id` | `NO ACTION` | `ON DELETE RESTRICT` |
| `complaints` | `user_id` | `NO ACTION` | `ON DELETE RESTRICT` |
| `complaints` | `assigned_to` | `NO ACTION` | `ON DELETE RESTRICT` |
| `waiting_list` | `user_id` | `NO ACTION` | `ON DELETE RESTRICT` |

`NO ACTION` and `RESTRICT` differ only in deferrability, so this is a clarity change, not a behavior change.
The value is in the error: a named `RESTRICT` violation tells the operator that hard delete is unsupported,
where a mid-cascade `NO ACTION` abort reads as a bug.

Soft delete via the existing `users.deleted_at` remains the supported path. No anonymizing erasure RPC is
built; see `research.md` for why it is deferred rather than rejected.

## `0062` — orphan enum

| Type | Action | Reason |
|------|--------|--------|
| `video_privacy` | `DROP TYPE` | No table, view, function, or column in `public` references it. It is the sole remnant of the video feature that 007 decommissioned |

## Entities not changed

Recorded so a future reviewer does not re-raise them:

- `event_outbox.attempts` and its `CHECK (attempts <= 5)` are consistent with `MAX_ATTEMPTS = 5` in the
  dispatcher and with the branching in `reap_stuck_outbox_events`. No change.
- `booking_status`, `payment_status`, and the other three existing status enums are correct and untouched.
- `app_role` stays `(USER, ADMIN, SUPER_ADMIN)`. No `PRIEST` value is added.
- No `anon` or `authenticated` grants exist on the `auth` or `vault` schemas. Verified, not assumed.
