# Feature Specification: Schema Integrity Fixes

**Feature Branch**: `009-schema-integrity-fixes`

**Created**: 2026-08-19

**Status**: Draft

**Input**: Defects found during a direct review of the live local database (`supabase_db_church`, migrations applied through `0054`) cross-checked against the Studio schema visualizer export.

## Context

This spec exists because a schema review found three features that are broken right now, plus a set of
integrity gaps that the database currently permits. Every finding below was verified against the running
database, not inferred from migration files. Findings that turned out to be non-issues are recorded in
`research.md` so they are not raised again.

The review also established that the Studio schema export omits all `ON DELETE` clauses. Delete semantics
must be read from `pg_constraint`, never from the visualizer output.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Restore the three features that are silently dead (Priority: P1)

`vault.secrets` contains zero rows. Three separate code paths read from it and all fail without surfacing
an error to any user-visible log:

- A member submits a complaint. `submit_complaint_secure` looks up `COMPLAINTS_KEY`, finds nothing, and
  raises `COMPLAINT_KEY_MISSING`. The complaints feature is unusable.
- The `event-dispatcher` cron fires every minute. It builds its target URL from the `SUPABASE_URL` secret;
  with no secret the expression evaluates to `NULL` and `net.http_post` is called with a null URL. Every
  outbox row stays `PENDING` forever, so WhatsApp notifications, FCM pushes, and Paymob refunds never send.
- The `reconcile-payments` cron has the same null-URL failure, so nightly payment reconciliation never runs.

**Why this priority**: This is not a latent risk. Complaints, all outbound notification, and payment
reconciliation are non-functional in any environment where the vault was never provisioned. The refund path
means money is affected.

**Independent Test**: Provision the three secrets, then confirm a complaint round-trips through
`submit_complaint_secure` / `decrypt_complaint`, and confirm a seeded outbox row transitions out of
`PENDING`.

**Acceptance Scenarios**:

1. **Given** an empty `vault.secrets`, **When** the preflight check runs, **Then** it fails loudly naming
   each missing secret, rather than allowing a deploy that silently no-ops.
2. **Given** `COMPLAINTS_KEY` provisioned, **When** a member submits a complaint, **Then** the row is stored
   with an encrypted body and an admin can decrypt it.
3. **Given** `SUPABASE_URL` and `SERVICE_ROLE_KEY` provisioned, **When** `event-dispatcher` runs against a
   `PENDING` outbox row, **Then** the row leaves `PENDING`.

---

### User Story 2 - Close the unintended email registration path (Priority: P1)

The product authenticates by phone OTP, but `config.toml` has `enable_signup = true` under `[auth.email]`.
`handle_new_user` then hides the consequence rather than blocking it:

```sql
values (new.id, coalesce(nullif(new.phone, ''), new.id::text), ...)
```

An email signup with no phone number satisfies the `phone NOT NULL UNIQUE` constraint by falling back to the
user's UUID as their phone number. The account is created successfully, defaults to role `USER`, and appears
in admin screens with a UUID where a phone number should be.

**Why this priority**: It is an open registration path on a product that is supposed to have exactly one, and
the fallback makes the resulting junk accounts look legitimate.

**Independent Test**: Attempt an email signup and confirm it is rejected.

**Acceptance Scenarios**:

1. **Given** `[auth.email] enable_signup = false`, **When** an email signup is attempted, **Then** it is
   rejected.
2. **Given** a user record whose phone did not come from OTP, **When** it is created, **Then** the system
   fails loudly instead of substituting the UUID.

---

### User Story 3 - Make the database reject impossible data (Priority: P2)

The schema currently permits rows that no code path should ever produce. All of these were checked against
live data and **zero violating rows exist**, so each constraint can be added and validated immediately with
no data repair step.

| Gap | Current state |
|-----|---------------|
| `service_slots` slot ending before it starts | Only `schedule_range` is guarded, and that column is nullable, so a null-range slot has no ordering guarantee |
| `service_slots.capacity`, `service_slots.price` | No `>= 0` constraint |
| `bookings.seat_count` | No `>= 1` constraint; zero or negative breaks capacity arithmetic in `book_slot` and `active_booking_count` |
| `payments.amount` | No `>= 0` constraint, while `bookings.paid_amount` has exactly that check |
| `media_assets.content_type` / `content_id` | Polymorphic pair with no both-or-neither constraint, so either half can be set alone |
| `service_slots.status`, `waiting_list.status` | Free `text` with a default and no constraint, while five other status columns are enums. A typo is accepted silently |
| `bookings.status` | Carries a redundant CHECK re-listing all six `booking_status` values; must be edited every time the enum grows |

**Why this priority**: These are correctness guardrails, not active incidents. They matter most because
feature 008 will build new money paths on top of `service_slots` and `bookings`.

**Independent Test**: For each constraint, attempt the invalid insert and confirm it is rejected.

**Acceptance Scenarios**:

1. **Given** the new constraints, **When** a slot is inserted with `ends_at <= starts_at`, **Then** it is
   rejected.
2. **Given** the new constraints, **When** a booking is inserted with `seat_count = 0`, **Then** it is rejected.
3. **Given** `slot_status` and `waitlist_status` enums, **When** an unrecognized status string is written,
   **Then** it is rejected.
4. **Given** the enum conversion, **When** existing RPCs compare status values, **Then** every existing
   comparison still resolves.

---

### User Story 4 - Make the tenant scaffolding internally correct (Priority: P2)

Constitution line 22 is authoritative: *"**Single church** deployment. Tenant scaffolding stays internal; no
multi-church UI or data entry ever ships."* Because only `tenant_id 1` will ever exist, none of the following
can currently fire. They are being fixed so the scaffolding is not self-contradictory, **not** because
multi-church is a target. No tenant-isolation test suite is in scope, and no ADR amending line 22 is being
requested.

- `payments_monthly` has PK `(month)` alone — the only rollup with no tenant-scoping key, where
  `bookings_monthly` and `slot_utilization_monthly` both key on the tenant-scoped `service_id`.
  `materialize_analytics` compounds it with an unscoped `DELETE FROM payments_monthly WHERE month = m`
  followed by an `INSERT` that omits `tenant_id`.
- `audit_log` has no `tenant_id` column at all, and its policy is a bare `USING is_admin()`.
- `whatsapp_optins` has PK `(phone)` alone, is the only table whose `tenant_id` is nullable and lacks
  `DEFAULT tenant_id()`, and its policy has no tenant predicate.

**Why this priority**: Unreachable under the ratified product truth, but they are the kind of defect that
looks like a security hole to the next reviewer and costs a re-investigation every time.

**Independent Test**: Confirm each table's key and default match the pattern used by every other table.

**Acceptance Scenarios**:

1. **Given** the corrected keys, **When** `materialize_analytics` runs twice, **Then** it is idempotent and
   scoped to the calling tenant.
2. **Given** `audit_log.tenant_id`, **When** an audit row is written, **Then** it carries the tenant.
3. **Given** `whatsapp_optins`, **When** a row is inserted, **Then** `tenant_id` is never null.

---

### User Story 5 - Remove the role abstraction that does not exist (Priority: P3)

`is_admin_or_priest()` has a body of `select public.is_admin()`. `app_role` is `(USER, ADMIN, SUPER_ADMIN)` —
there is no `PRIEST` value. `priests` has no foreign key to `users`, so a priest row cannot be linked to the
account it represents, while `complaints.assigned_to` points at `users(id)`. A test file for the intended
behavior, `supabase/tests/0005_priest_self_assign_test.sql`, still exists.

The decision is to delete the abstraction rather than build the role.

Eight live policies reference the function and must be recreated **before** it is dropped. `DROP FUNCTION
... CASCADE` would drop the policies themselves and silently remove access control from eight tables:

`announcements`, `faq`, `priests`, `service_slots`, `services` (each `admin write`, `ALL`), and
`bookings_monthly`, `payments_monthly`, `slot_utilization_monthly` (each `p_analytics_read_admin`, `SELECT`).

**Why this priority**: Pure clarity work with no behavior change, but the drop ordering makes it dangerous to
do carelessly.

**Independent Test**: Confirm all eight policies still enforce admin-only access, and that the function no
longer exists.

**Acceptance Scenarios**:

1. **Given** the recreated policies, **When** a non-admin reads each of the eight tables, **Then** access is
   denied exactly as before.
2. **Given** the migration, **When** it completes, **Then** `is_admin_or_priest` does not exist and no policy
   was dropped.

---

### User Story 6 - Make user deletion semantics explicit (Priority: P3)

Deleting an `auth.users` row cascades into `public.users`, then aborts against `NO ACTION` foreign keys from
`bookings.user_id`, `complaints.user_id`, `complaints.assigned_to`, and `waiting_list.user_id`. The cascade
promises a hard delete that cannot complete for any user who has ever booked.

`users.deleted_at` already exists, so soft delete is the intended path. The fix is to state that in the
schema: make those foreign keys explicit `ON DELETE RESTRICT` and document hard delete as unsupported.

An anonymizing erasure RPC is **deliberately out of scope**. It is noted here because Egypt's PDPL
(Law 151/2018) grants erasure rights, so this will likely need revisiting — but nothing today requires it and
building it now would be speculative.

**Why this priority**: No user is blocked. It is a latent trap for whoever first tries to delete an account.

**Independent Test**: Attempt to delete a user who has a booking and confirm a clear rejection.

**Acceptance Scenarios**:

1. **Given** explicit `RESTRICT`, **When** deleting a user with a booking, **Then** it is rejected with a
   clear constraint error.
2. **Given** `users.deleted_at`, **When** an account is soft-deleted, **Then** the member loses access and
   the booking and payment history is retained.

---

### User Story 7 - Realign the constitution with the shipped product (Priority: P3)

Constitution lines 24-25 still present "Two video types" as owner-ratified Product Truth. Feature 007
decommissioned video entirely. The database confirms the removal is complete except for one orphan: the
`video_privacy` enum, which no table references.

This matters beyond tidiness: feature 008 planning reads the constitution as Product Truth, so stale text
will actively misdirect it toward a cancelled feature.

Governance requires an owner decision in `docs/adr/` plus a date bump for any amendment, so this ships as an
ADR recording the already-made pivot, then the constitution edit.

**Why this priority**: Documentation only, but it should land before 008 planning begins.

**Independent Test**: Confirm the enum is gone and no constitution line describes video as current product truth.

**Acceptance Scenarios**:

1. **Given** the migration, **When** it completes, **Then** `video_privacy` no longer exists.
2. **Given** the ADR, **When** the constitution is amended, **Then** lines 24-25 describe the event booking
   model and the version is bumped.

---

### Edge Cases

- What happens if the `service_slots.status` enum conversion misses a value that only application code
  writes? Nothing in SQL ever writes `'CLOSED'` — only comparisons exist. The write path must be located
  before conversion, or admin slot-closing breaks. See `research.md`.
- What happens to a `waiting_list` row left in `OFFERED`? Nothing clears it. There is no terminal state, so
  offered entries accumulate. Recorded as an open question; no values are being invented to fix it.
- What happens if `payments_monthly`'s PK changes while a rollup is mid-flight? The table holds zero rows and
  is fully rebuilt by `materialize_analytics`, so the change is lossless.
- What happens if a CHECK is added to a table that already violates it? Verified not to apply — all counts are
  zero. If this is re-run against production data, each count must be re-verified first.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A preflight check MUST fail loudly, naming each missing secret, when any of `COMPLAINTS_KEY`,
  `SUPABASE_URL`, or `SERVICE_ROLE_KEY` is absent from `vault.secrets`.
- **FR-002**: Local development MUST provision the three vault secrets reproducibly, using the in-network
  Kong address rather than a loopback address, since the database container's loopback is itself.
- **FR-003**: Production vault provisioning MUST be documented in the ops runbook.
- **FR-004**: Email signup MUST be disabled.
- **FR-005**: `handle_new_user` MUST NOT substitute a UUID for a missing phone number.
- **FR-006**: `service_slots` MUST reject `ends_at <= starts_at` regardless of whether `schedule_range` is null.
- **FR-007**: `service_slots.capacity` and `service_slots.price` MUST reject negative values.
- **FR-008**: `bookings.seat_count` MUST reject values below 1.
- **FR-009**: `payments.amount` MUST reject negative values.
- **FR-010**: `media_assets` MUST require `content_type` and `content_id` to be both set or both null.
- **FR-011**: `service_slots.status` MUST be constrained to `(OPEN, CLOSED)` and `waiting_list.status` to
  `(WAITING, OFFERED)` — the exact values in use, with none invented.
- **FR-012**: The redundant `bookings.status` CHECK MUST be dropped, leaving the enum as the single source of truth.
- **FR-013**: `payments_monthly` MUST key on `(tenant_id, month)`.
- **FR-014**: `materialize_analytics` MUST scope both its delete and its insert by tenant.
- **FR-015**: `audit_log` MUST carry a non-null `tenant_id` defaulting to `tenant_id()`, and its policy MUST
  include a tenant predicate.
- **FR-016**: `whatsapp_optins` MUST key on `(tenant_id, phone)`, default `tenant_id` to `tenant_id()`, be
  `NOT NULL`, and its policy MUST include a tenant predicate.
- **FR-017**: All eight policies referencing `is_admin_or_priest()` MUST be recreated against `is_admin()`
  **before** the function is dropped, with no use of `CASCADE`.
- **FR-018**: `is_admin_or_priest()` and `supabase/tests/0005_priest_self_assign_test.sql` MUST be removed,
  and the test deregistered from `run_all.sql`.
- **FR-019**: The four `NO ACTION` foreign keys into `users` MUST become explicit `ON DELETE RESTRICT`, with
  hard delete documented as unsupported.
- **FR-020**: The orphan `video_privacy` enum MUST be dropped.
- **FR-021**: An ADR MUST record the video-to-event-booking pivot, and constitution lines 24-25 MUST be
  amended with a version bump.
- **FR-022**: Every migration MUST be forward-only, numbered from `0055`, and paired with a test registered in
  `run_all.sql`.
- **FR-023**: No migration may edit an applied migration in place.

### Key Entities

- **`vault.secrets`**: Supabase-managed. Holds `COMPLAINTS_KEY`, `SUPABASE_URL`, `SERVICE_ROLE_KEY`. Read via
  the `vault.decrypted_secrets` view. Confirmed to have no `anon` or `authenticated` grants.
- **`slot_status`**, **`waitlist_status`**: New enums replacing free-text status columns.
- **`payments_monthly`**, **`audit_log`**, **`whatsapp_optins`**: The three tables whose tenant scaffolding
  deviates from the pattern every other table follows.
- **`is_admin_or_priest()`**: Function being removed. Depended on by eight live policies.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A complaint can be submitted and decrypted end to end.
- **SC-002**: A seeded outbox row leaves `PENDING` within two dispatcher cycles.
- **SC-003**: A deploy with any vault secret missing fails at preflight rather than starting.
- **SC-004**: Email signup is rejected.
- **SC-005**: Each of the twelve new or changed constraints rejects its invalid input, proven by a test that
  asserts the rejection rather than asserting an absence of rows.
- **SC-006**: All eight recreated policies still deny non-admin access, verified after `is_admin_or_priest()`
  is gone.
- **SC-007**: `materialize_analytics` run twice produces identical rollups.
- **SC-008**: The full SQL suite passes with zero TAP failures, verified by parsing TAP output — never by
  trusting the `psql` exit code, which returns 0 even when assertions fail.
- **SC-009**: Deleting a user with a booking is rejected with a named constraint.
- **SC-010**: No constitution line presents video as current product truth.

## Assumptions

- Single-church deployment per constitution line 22. Tenant fixes make the scaffolding self-consistent and
  are explicitly not a step toward multi-church.
- The zero-violating-row counts were taken from the local database. They must be re-verified against
  production before the constraint migrations are applied there.
- `reap_stuck_outbox_events` is correct as written and out of scope; see `research.md`.
- The `attempts <= 5` CHECK on `event_outbox` is consistent with `MAX_ATTEMPTS = 5` in the dispatcher and needs
  no change.
- No `anon` or `authenticated` grants exist on the `auth` or `vault` schemas; this is verified, not assumed.
- Erasure/anonymization tooling is out of scope.
