# Schema Contracts: Schema Integrity Fixes

This feature exposes no new HTTP surface. Its contracts are the guarantees the database makes to its callers:
which inputs are rejected, which functions exist with which signatures, and which policies enforce which
access. Each contract below is stated as an observable assertion so the paired SQL test can be written directly
from it.

Every test is transactional (`BEGIN ... ROLLBACK`) and registered in `supabase/tests/run_all.sql`. Rejection
contracts must be proven by asserting the rejection — `throws_ok` or an equivalent — never by asserting an
absence of rows, which passes vacuously when the insert never ran.

## Function contracts

### `public.vault_preflight()`

| | |
|---|---|
| Signature | `vault_preflight() returns setof text` |
| Volatility | `stable` |
| Security | `security definer`, `set search_path to ''` |
| Caller | Deploy tooling and the smoke-test gate, as the service role |

**Contract**

- Returns one row per required secret that is absent from `vault.decrypted_secrets`.
- Returns zero rows when all three of `COMPLAINTS_KEY`, `SUPABASE_URL`, `SERVICE_ROLE_KEY` are present.
- Returns names only. No secret value appears in the result, in an error message, or in any log line.
- Is read-only. Calling it never provisions, mutates, or creates a secret.

**Assertions**

1. With all three secrets present, the function returns zero rows.
2. With one secret removed inside a transaction, the function returns exactly that one name.
3. The function's result columns contain no value from `vault.decrypted_secrets.decrypted_secret`.

### `public.handle_new_user()`

| | |
|---|---|
| Signature | `handle_new_user() returns trigger` |
| Security | `security definer`, `set search_path to ''` |

**Contract**

- Given an `auth.users` row with a non-empty phone, inserts the mirrored `public.users` row with that phone.
- Given an `auth.users` row with a null or empty phone, raises. It does not insert a row, and in particular it
  does not substitute `new.id::text`.
- Remains idempotent on `id` via `on conflict (id) do nothing`.

**Assertions**

1. Inserting an `auth.users` row with a phone produces a `public.users` row carrying that phone.
2. Inserting an `auth.users` row with no phone raises, and `public.users` gains no row.
3. No `public.users.phone` value in the database parses as a UUID.

### `public.materialize_analytics()`

**Contract**

- Both the `DELETE` and the `INSERT` against `payments_monthly` are scoped by `tenant_id`.
- Two consecutive invocations produce byte-identical rollup contents.
- Every inserted `payments_monthly` row carries a non-null `tenant_id`.

**Assertions**

1. Run twice; the full contents of `payments_monthly` compare equal after the second run.
2. After a run, `count(*) filter (where tenant_id is null) = 0`.
3. The function source contains a `tenant_id` predicate on its `payments_monthly` delete.

### `public.is_admin_or_priest()`

**Contract**: does not exist after `0060`.

**Assertion**: `to_regprocedure('public.is_admin_or_priest()') is null`.

## Rejection contracts

Each row is one assertion: attempt the invalid write, confirm it is rejected by the named constraint.

| Target | Invalid input | Must be rejected by |
|--------|--------------|--------------------|
| `service_slots` | `ends_at = starts_at` | `service_slots_time_order_chk` |
| `service_slots` | `ends_at < starts_at` | `service_slots_time_order_chk` |
| `service_slots` | `ends_at < starts_at` with `schedule_range` null | `service_slots_time_order_chk` |
| `service_slots` | `capacity = -1` | `service_slots_capacity_nonneg_chk` |
| `service_slots` | `price = -1` | `service_slots_price_nonneg_chk` |
| `bookings` | `seat_count = 0` | `bookings_seat_count_min_chk` |
| `bookings` | `seat_count = -1` | `bookings_seat_count_min_chk` |
| `payments` | `amount = -1` | `payments_amount_nonneg_chk` |
| `media_assets` | `content_type` set, `content_id` null | `media_assets_polymorphic_chk` |
| `media_assets` | `content_type` null, `content_id` set | `media_assets_polymorphic_chk` |
| `service_slots` | `status = 'PENDING'` | invalid input value for enum `slot_status` |
| `waiting_list` | `status = 'EXPIRED'` | invalid input value for enum `waitlist_status` |
| `whatsapp_optins` | `tenant_id = null` | `NOT NULL` violation |
| `users` | delete a user who has a booking | `ON DELETE RESTRICT` on `bookings.user_id` |

The third `service_slots` row is not redundant with the second. It is the specific case the old
`schedule_range`-only guard missed, and it is the reason this constraint exists.

## Acceptance contracts

Positive paths that must keep working. A constraint that rejects valid data is as much a defect as one that
accepts invalid data.

| Target | Valid input | Must be accepted |
|--------|------------|-----------------|
| `service_slots` | `ends_at > starts_at`, `capacity = 0`, `price = 0` | Yes — free and zero-capacity slots are legitimate |
| `bookings` | `seat_count = 1` | Yes |
| `payments` | `amount = 0` | Yes |
| `media_assets` | both `content_type` and `content_id` null | Yes |
| `media_assets` | both `content_type` and `content_id` set | Yes |
| `service_slots` | `status = 'CLOSED'` sent as a string | Yes — this is the admin app's write path via PostgREST |
| `waiting_list` | `status = 'OFFERED'` | Yes — written by `promote_waiting_list` |
| `bookings` | every value of `booking_status` | Yes — after the redundant CHECK is dropped, the enum alone governs |

## Enum contracts

| Enum | Exact value set | Nothing else |
|------|----------------|--------------|
| `slot_status` | `OPEN`, `CLOSED` | No `PENDING`, `DRAFT`, or `ARCHIVED` |
| `waitlist_status` | `WAITING`, `OFFERED` | No `EXPIRED`, `DECLINED`, or `CONVERTED` |
| `app_role` | `USER`, `ADMIN`, `SUPER_ADMIN` | Unchanged. No `PRIEST` |
| `video_privacy` | Does not exist | — |

**Assertions**

1. `enum_range(null::slot_status)` equals exactly `{OPEN,CLOSED}`.
2. `enum_range(null::waitlist_status)` equals exactly `{WAITING,OFFERED}`.
3. `to_regtype('video_privacy') is null`.
4. Every comparison site in `0008`, `0015`, `0017`, `0028`, `0048`, `0053` still resolves — proven by
   exercising the RPCs that contain them, not by reading the files.

## View grant contracts

`0058` must drop and recreate `v_available_slots` and `v_schedule_today` to convert `service_slots.status`. A
recreated view loses its grants, so these are contracts, not incidental details.

| View | Role | Privilege |
|------|------|-----------|
| `v_available_slots` | `anon` | `SELECT` |
| `v_available_slots` | `authenticated` | `SELECT` |
| `v_schedule_today` | `anon` | `SELECT` |
| `v_schedule_today` | `authenticated` | `SELECT` |

Both views keep `security_invoker = true`.

**Assertions**

1. `has_table_privilege('anon', 'public.v_available_slots', 'SELECT')` — and the other three combinations.
2. Both views' `reloptions` still contain `security_invoker=true`.

This restores what `supabase/migrations/0050_explicit_read_grants.sql:63-64` established. A missing grant here
does not error anywhere in SQL — the views still work for the service role — it just empties the mobile app's
slot listing.

## Policy contracts

The eight policies that currently reference `is_admin_or_priest()` must, after `0060`, still exist and still
deny non-admin access.

| Table | Policy | Command | Non-admin result |
|-------|--------|---------|-----------------|
| `announcements` | `announcements admin write` | `ALL` | Denied on write |
| `faq` | `faq admin write` | `ALL` | Denied on write |
| `priests` | `priests admin write` | `ALL` | Denied on write |
| `service_slots` | `service_slots admin write` | `ALL` | Denied on write |
| `services` | `services admin write` | `ALL` | Denied on write |
| `bookings_monthly` | `p_analytics_read_admin` | `SELECT` | Denied on read |
| `payments_monthly` | `p_analytics_read_admin` | `SELECT` | Denied on read |
| `slot_utilization_monthly` | `p_analytics_read_admin` | `SELECT` | Denied on read |

**Assertions**

1. All eight policies are present in `pg_policies` after the migration. Counting them is the assertion that
   catches an accidental `CASCADE`.
2. For each of the eight, a non-admin session is denied — asserted *after* `is_admin_or_priest()` is gone.
3. No policy definition anywhere in `pg_policies` still contains the string `is_admin_or_priest`.

Assertion 2 is the one that matters. A dropped policy leaves the table readable and writable by anyone who
passes RLS's default, so asserting the policy's *existence* alone would not prove access is still controlled.

## Tenant scaffolding contracts

| Object | Contract |
|--------|----------|
| `payments_monthly` | Primary key is `(tenant_id, month)` |
| `audit_log` | `tenant_id` is `bigint NOT NULL DEFAULT tenant_id()`; its policy contains a tenant predicate |
| `whatsapp_optins` | Primary key is `(tenant_id, phone)`; `tenant_id` is `NOT NULL DEFAULT tenant_id()`; its policy contains a tenant predicate |

**Assertions**

1. Each primary key's column list matches exactly, read from `pg_index` / `pg_constraint`.
2. Inserting into `audit_log` and `whatsapp_optins` without naming `tenant_id` yields `tenant_id()`.
3. Both policies' `qual` text references `tenant_id`.

These are shape assertions, not isolation assertions. Per constitution line 22 only `tenant_id 1` will ever
exist, so no test attempts to prove cross-tenant separation.

## Foreign key contracts

| Constraint | Delete action |
|-----------|--------------|
| `bookings.user_id` → `users.id` | `RESTRICT` |
| `complaints.user_id` → `users.id` | `RESTRICT` |
| `complaints.assigned_to` → `users.id` | `RESTRICT` |
| `waiting_list.user_id` → `users.id` | `RESTRICT` |

**Assertions**

1. `pg_constraint.confdeltype = 'r'` for all four.
2. Deleting a `users` row that has a booking raises, naming the constraint.
3. Deleting the corresponding `auth.users` row also raises, since the cascade into `public.users` hits the same
   restriction.

Read these from `pg_constraint`. The Studio visualizer export omits every `ON DELETE` clause, so it cannot be
used to verify this section.

## End-to-end contracts

Three contracts cannot be proven by a schema assertion, because the defect they cover is a runtime no-op rather
than a permitted-but-invalid row.

| Contract | Proof |
|----------|-------|
| Complaints work | A complaint submitted through `submit_complaint_secure` is retrievable through `decrypt_complaint` with matching plaintext |
| Dispatch works | A seeded `event_outbox` row leaves `PENDING` within two dispatcher cycles |
| Email signup is closed | An email signup attempt against the local stack is rejected |

The first two are the reason US1 is P1: they currently fail silently, and a passing schema suite would not
notice.
