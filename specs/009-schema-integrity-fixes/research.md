# Phase 0 Research: Schema Integrity Fixes

All findings below were verified against the running local database (`supabase_db_church`, migrations applied
through `0054`) or against source in this repository. Nothing here is inferred from the Studio visualizer
export alone.

## Resolved unknowns

### Does anything write `service_slots.status = 'CLOSED'`?

**Decision**: Yes. Converting the column to a `slot_status` enum with values `(OPEN, CLOSED)` is safe.

**Rationale**: No SQL migration ever writes `'CLOSED'` — every reference is a comparison
(`status <> 'CLOSED'`, `status = 'CLOSED'`) in `0008`, `0015`, `0017`, `0028`, `0048`, `0053`. The write lives
in the admin Flutter app at `apps/admin/lib/features/slots/slots_admin_screen.dart:37`:

```dart
await widget.db.from('service_slots').update({'status': 'CLOSED'}).eq('id', r['id']);
```

PostgREST sends the value as a string, which Postgres casts to the enum, so the conversion does not break this
write path.

**Alternatives considered**: A `CHECK (status IN ('OPEN','CLOSED'))` instead of an enum. Rejected for
consistency — five other status columns in this schema are enums, and the enum gives the same guarantee while
matching the established pattern.

### What is the complete value set for `waiting_list.status`?

**Decision**: `(WAITING, OFFERED)`. No other values are invented.

**Rationale**: `WAITING` is the column default and is compared in `0008_booking_state_machine.sql:89,117`.
`OFFERED` is written by `promote_waiting_list` at `0008_booking_state_machine.sql:99`. Those are the only two
values anywhere in the codebase. The table is currently empty, so conversion is lossless.

**Alternatives considered**: Adding plausible lifecycle values such as `EXPIRED`, `DECLINED`, or `CONVERTED`.
Rejected as speculative — no code writes or reads them, and inventing enum values to fill a perceived gap would
be designing for a requirement nobody has stated. The genuine lifecycle gap is recorded as an open question
below instead.

### Can `event_outbox.attempts` exceed its `CHECK (attempts <= 5)`?

**Decision**: No. Not a defect. Out of scope.

**Rationale**: This was flagged as a possible wedge — a row at `attempts = 5` being reset to `PENDING` and then
incremented to 6, aborting the transaction on the CHECK. Reading
`reap_stuck_outbox_events` disproves it. The function branches explicitly:

- `attempts < 5` → reset to `PENDING`, `attempts = attempts + 1` (so the maximum written is 5)
- `attempts >= 5` → transition to `FAILED` without incrementing

The dispatcher agrees: `MAX_ATTEMPTS = 5`, and `event-dispatcher/index.ts:358-368` computes
`attempts = row.attempts + 1` then writes `FAILED` when `attempts >= MAX_ATTEMPTS`. The highest value ever
persisted is 5. `REFUND_MAX_ATTEMPTS = 3` is stricter still.

### Is the `auth` or `vault` schema exposed to client roles?

**Decision**: No. Not a defect.

**Rationale**: `information_schema.role_table_grants` returns zero rows for `anon` and `authenticated` across
both schemas. `vault.decrypted_secrets` is not reachable through PostgREST.

### What address should `SUPABASE_URL` hold for local development?

**Decision**: `http://kong:8000`.

**Rationale**: The secret is read from inside the database container by `pg_net`. `127.0.0.1` there resolves to
the database container itself, not to Kong. `kong` resolves to `172.18.0.8` on the compose network, confirmed
with `getent hosts kong` from inside `supabase_db_church`. `supabase_kong_church` resolves to the same address
and would also work; `kong` is the shorter alias and matches Supabase's own local convention.

### Can the new constraints be added without a data repair step?

**Decision**: Yes. Every constraint can be added and validated in one step.

**Rationale**: Measured against live data, every violating-row count is zero:

```text
slots_bad_order=0  slots_neg_cap=0  slots_neg_price=0  seat_lt1=0
pay_neg=0  media_half=0  audit_rows=0  wa_null_tenant=0  pm_rows=0
```

`audit_log` and `payments_monthly` are both empty, which makes adding `audit_log.tenant_id NOT NULL` and
changing the `payments_monthly` primary key trivial and lossless.

**Caveat**: These counts are from the local database. They must be re-measured before the same migrations are
applied to production, where the counts may differ.

### How many policies depend on `is_admin_or_priest()`, and what is the safe drop order?

**Decision**: Eight live policies. Recreate all eight against `is_admin()` first, then drop the function.
Never use `CASCADE`.

**Rationale**: Queried from `pg_policies` rather than from migration history, since later migrations supersede
earlier ones:

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

`DROP FUNCTION public.is_admin_or_priest() CASCADE` would drop all eight policies, removing access control from
eight tables while appearing to succeed. The migration must recreate then drop, and the paired test must assert
the policies still deny non-admin access *after* the function is gone.

Because the function body is exactly `select public.is_admin()`, the substitution is behavior-preserving.

### What should hard user deletion do?

**Decision**: Soft delete only. Make the four foreign keys explicit `ON DELETE RESTRICT` and document hard
delete as unsupported. No erasure RPC.

**Rationale**: `users.deleted_at` already exists, so soft delete was the design intent. The current state is
worse than either choice — `auth.users` → `public.users` is `ON DELETE CASCADE`, which promises a hard delete
that then aborts against `NO ACTION` keys from `bookings`, `complaints` (twice), and `waiting_list`. Making the
restriction explicit turns a confusing mid-cascade abort into a clear, named constraint error.

**Alternatives considered**: `ON DELETE CASCADE` down the chain — rejected because it destroys payment and
audit history, which reconciliation and refunds depend on. An anonymizing erasure RPC — deferred, not
rejected: Egypt's PDPL (Law 151/2018) grants erasure rights, so this will likely be needed, but nothing today
requires it and building it now would be speculative.

## Non-findings, recorded so they are not re-raised

- **The Studio visualizer is not inventing constraints.** It does omit every `ON DELETE` clause, which is why
  `users_id_fkey` appears bare when it is actually `ON DELETE CASCADE`, and `faq_category_id_fkey` is actually
  `ON DELETE SET NULL`. Read delete semantics from `pg_constraint`, never from the export.
- **`auth.users` has no self-referencing foreign key.** `pg_constraint` returns none. When the export renders
  `users_id_fkey ... REFERENCES auth.users(id)` under the `auth` schema, it is showing `public.users`'
  constraint on the table it points at.
- **`reap_stuck_outbox_events` is correct.** See above.
- **`handle_new_user` is correctly hardened.** `SECURITY DEFINER` with `SET search_path TO ''`, fully qualified
  writes, and `on conflict (id) do nothing` for idempotency. Its only defect is the UUID-as-phone fallback.
- **`is_super_admin()` is correct.** It reads `public.users.role`, not GoTrue's `auth.users.is_super_admin`
  column. The two are unrelated and the right one is being used.
- **Video removal is otherwise complete.** No table, view, function, or column in `public` matches `%video%`.
  The `video_privacy` enum is the sole remnant.

## Open questions — deliberately not fixed here

These are recorded because they surfaced during review, but each needs a product decision rather than a schema
change, and inventing an answer would be worse than leaving them visible.

1. **`waiting_list` has no terminal state.** `promote_waiting_list` sets `OFFERED` and nothing ever clears it.
   An offered entry stays `OFFERED` forever, so the list accumulates and there is no way to express that an
   offer expired, was declined, or converted to a booking. Needs a lifecycle decision, likely as part of 008.

2. **`service_slots` carries two sources of truth for its time window.** `starts_at`/`ends_at` and
   `schedule_range` can disagree, and nothing keeps them in sync. This spec adds the missing
   `ends_at > starts_at` guard but does not resolve the duplication. Options are a generated column, a trigger,
   or dropping one representation — all beyond a constraint fix.

3. **Slot closing bypasses the RPC-only write model.** `slots_admin_screen.dart:37` updates
   `service_slots.status` directly through PostgREST. Constitution II requires state transitions to go through
   `SECURITY DEFINER` RPCs, and the 008 handoff notes that 008 depends on the RPC-only write model. This is a
   deviation, not a schema defect, so it is flagged rather than fixed here.

4. **`priests` cannot be linked to an account.** With `is_admin_or_priest()` removed, `priests` is purely a
   content directory while `complaints.assigned_to` references `users(id)`. If priests are ever meant to log in
   and self-assign complaints, both an `app_role` value and a `priests.user_id` foreign key will be needed.

## Incidental observation

`apps/mobile/.dart_tool/admin/` contains a stale copy of the admin app's sources, including
`slots_admin_screen.dart`. It is build-tool output, not a second implementation, but it pollutes
repository-wide greps. Not in scope.
