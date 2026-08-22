# API Contracts: Review Findings Remediation

**Feature**: 010-fix-review-findings · **Date**: 2026-08-21

Contracts this feature changes or freezes. Formats follow existing repo conventions (spec 009 `contracts/schema-contracts.md` style).

## 1. SQL RPC contract — `transition_booking_status`

```sql
public.transition_booking_status(
  p_booking_id bigint,
  p_action     text,
  p_new_status booking_status
) returns bookings   -- SECURITY DEFINER, SET search_path = public
```

- Authorization (0064): `is_admin() OR owner OR auth.role() = 'service_role'`; no action-string escape hatches
- Denial: exception path, zero rows changed; audit row records the denied attempt context as today
- Privileges: `REVOKE ALL ... FROM PUBLIC, anon, authenticated; GRANT EXECUTE ... TO authenticated, service_role;`
- Negative test obligations: non-owner + apply_payment → denial assertion (`ROW_COUNT = 0` semantics per RLS test rules); owner + apply_payment → success; service_role → success

## 2. SQL RPC contracts — payment lifecycle (gateway-callable surface)

```sql
public.record_booking_payment(
  p_booking_id bigint,
  p_amount     numeric,
  p_gateway_ref text
) returns payments    -- SECURITY DEFINER
```

- Existing behavior frozen: insert + `apply_payment` advance (owner-initiated recording keeps working)

```sql
public.create_pending_payment(          -- NEW, additive in 0064
  p_booking_id  bigint,
  p_amount      numeric,
  p_gateway_ref text
) returns payments     -- SECURITY DEFINER
```

- Insert-only: creates the `CREATED` row checkout needs before gateway redirect; NO status advance
- Authorization: booking owner or service role; REVOKE-then-grant per hardening rule
- Rationale for a dedicated RPC instead of a mode flag on `record_booking_payment`: avoids boolean-flag parameter; one procedure per state intent matches the gateway's function-per-intent shape

```sql
public.mark_payment_failed(             -- NEW, additive in 0064
  p_payment_id bigint
) returns payments     -- SECURITY DEFINER
```

- Sets status `FAILED` from `CREATED`/`PENDING` only (idempotent on already-FAILED); never touches `PAID` rows — stale/cancelled money keeps flowing to `REFUND_PENDING` via existing race semantics
- Authorization: service role only (checkout/webhook/reconcile are the sole callers); REVOKE ALL FROM PUBLIC, anon, authenticated → GRANT to service_role
- Test obligations (registered in run_all.sql): non-service caller denied (zero rows); FAILED transition succeeds; PAID row untouched

All three: callers restricted to the gateway module (service-role client); direct table writes remain forbidden everywhere else

## 3. HTTP error contract (all edge functions — narrowed, frozen)

```json
{ "error": "UNAUTHORIZED|FORBIDDEN|BAD_REQUEST|UPSTREAM_ERROR|INTERNAL", "message_ar": "<catalog sentence>" }
```

- No third field carrying library/exception/upstream text on any status
- Success shapes unchanged
- Test obligation: every endpoint's failure-path test asserts absence of leak substrings

## 4. Dart seam contract — admin repositories

```dart
abstract interface class <Feature>Repository {
  Future<Either<Failure, List<T>>> list...();
  Future<Either<Failure, T>> <verb><Noun>(...);   // commands return new state/result
}
```

- One repository file per feature under `apps/admin/lib/features/<f>/`
- Zero `Supabase.instance` / `.from(` / `.rpc(` outside repositories (grep-enforced)
- No `dynamic` database handles anywhere in admin lib
- Errors mapped at repository boundary to `Failure` (mobile's `core/failure.dart` shape reused)
- Auth provider contract: role decision from `users.role` only; no RPC to removed functions; no silent catch-through between branches

## 5. Portal client contract (test-apps)

- Clients constructed with anon key only; custom-key parameter removed from factory
- All flows authenticate via seeded accounts (`+2010000000xx` fixtures) with setup-generated passwords from untracked local file
- Repository-wide scan: zero service-role JWTs, zero password literals in committed files

## 6. Documentation contract

- Enumerations in conventions.md §Enums diff empty against live `pg_type` values
- AGENTS.md admin route guard: `ADMIN|SUPER_ADMIN`, pointer to ADR-0002 for PRIEST removal
