# Quickstart & Verification Guide: 007-backend-security-fixes

**Feature**: Backend Security and Correctness Fixes  
**Branch**: `007-backend-security-fixes`  
**Shell**: **bash** (this session's shell — not PowerShell). Use forward slashes and `/dev/null`.  
**Purpose**: gates that actually run. Every command below was corrected against the live container
layout; the first draft used `psql -f /tests/<file>`, which fails because **`/tests` is not mounted
inside `supabase_db_church`**.

---

## 1. Prerequisites & environment setup

```bash
npx supabase status || npx supabase start
```

The edge runtime container must be **running**, not merely present. `docker ps --filter` prints an
empty table and exits 0 when the container is stopped, so it is not a check:

```bash
docker ps --format '{{.Names}}' | grep -q '^supabase_edge_runtime_church$' \
  || npx supabase functions serve --no-verify-jwt &
```

### Paymob placeholders are required for Gate 6

0053 adds module-scope validation to `paymob-checkout`: it throws if `PAYMOB_API_KEY`,
`PAYMOB_INTEGRATION_ID`, `PAYMOB_IFRAME_ID`, or `PAYMOB_HMAC_SECRET` is absent, empty, or the string
`"0"`. Without values the function will not boot and Gate 6 fails for the wrong reason. Put
non-`"0"` placeholders in `supabase/functions/.env` for local runs:

```dotenv
PAYMOB_API_KEY=local-placeholder
PAYMOB_INTEGRATION_ID=999999
PAYMOB_IFRAME_ID=888888
PAYMOB_HMAC_SECRET=local-placeholder
```

**Do not** weaken the secret check to make the gate green, and **do not** add a new error code — the
error-code contract is frozen. These placeholders are local-only; the e2e script (Gate 7) needs real
staging Paymob and `TEST_*` secrets, supplied out of band and **never committed**.

---

## 2. Validation gates

### Gate 1 — Forward migrations apply cleanly

```bash
npx supabase db reset
```

*Expected*: zero errors, and in particular no `55P04 unsafe_new_enum_value_usage`. That error means
`SUPER_ADMIN` was added and referenced in the same transaction — the `ALTER TYPE` must stay alone in
`0052_super_admin_role.sql`.

Because eleven commits on `main` edited already-numbered migrations in place, `db reset` is currently
the **only** reliable route to a known-good schema. `supabase db push` against an older environment
will not produce the same result.

---

### Gate 2 — SQL regression suites

Suites are piped over **stdin**. `run_all.sql` cannot be used this way: its `\ir` paths do not resolve
from stdin, and the file has CRLF line endings, so `\r` must be stripped from any filename extracted
from it.

```bash
for f in supabase/tests/*.sql; do
  case "$(basename "$f")" in run_all.sql) continue ;; esac
  echo "── $(basename "$f")"
  docker exec -i supabase_db_church psql -U postgres -d postgres \
    -v ON_ERROR_STOP=1 --no-psqlrc < "$f" || echo "FAIL: $f"
done
```

*Expected*: every suite reports `PASS` / `ok` with zero failures, including the new
`0053_security_fixes_test.sql`.

**Watch for the nine legacy suites** that reference `remaining_capacity`, `available_seats`, or
`slot_status`: `0007`, `0008`, `0009`, `0010`, `0012`, `0021`, `0035`, `0037`, `0047`. Dropping
`service_slots.remaining_capacity` breaks any of them that read it. They keep their plain-assert style
(handoff decision 13) but must still compile.

---

### Gate 3 — Deno edge-function tests

```bash
deno test --allow-env --allow-net supabase/functions/
```

*Expected*: all assertions pass, including the new `reconcile-payments/index_test.ts` cases proving a
502/timeout leaves the payment in `CREATED` rather than `FAILED`.

---

### Gate 4 — Negative authorization

Grant-level denial raises `42501 insufficient_privilege`. This is the one place where asserting an
**exception** is correct; `AGENTS.md`'s "assert 0 rows affected, not exceptions" rule applies to
RLS-level denial and needs an explicit carve-out for grants (amended by this feature).

```bash
docker exec -i supabase_db_church psql -U postgres -d postgres --no-psqlrc <<'SQL'
BEGIN;
DO $$
BEGIN
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM public.apply_payment(1);
    RAISE EXCEPTION 'CRITICAL: apply_payment is callable by anon';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: apply_payment denied to anon';
  END;

  BEGIN
    PERFORM public.rbac_allows('ADMIN'::public.app_role, 'payments', 'update');
    RAISE EXCEPTION 'CRITICAL: rbac_allows is callable by anon';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: rbac_allows denied to anon';
  END;

  RESET ROLE;
  SET LOCAL ROLE authenticated;
  BEGIN
    UPDATE public.payments SET status = 'PAID' WHERE id = 1;
    RAISE EXCEPTION 'CRITICAL: direct UPDATE on payments is permitted';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: direct UPDATE on payments denied to authenticated';
  END;

  BEGIN
    DELETE FROM public.audit_log WHERE id = 1;
    RAISE EXCEPTION 'CRITICAL: direct DELETE on audit_log is permitted';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: direct DELETE on audit_log denied to authenticated';
  END;

  RESET ROLE;
END $$;
ROLLBACK;
SQL
```

*Expected*: four `PASS` notices, no `CRITICAL`.

Then confirm the replacement admin `SELECT` policies exist — dropping `p0_admin_all` without them
silently returns zero rows to admins and breaks
`apps/admin/lib/features/payments/payments_admin_screen.dart:15`:

```bash
docker exec -i supabase_db_church psql -U postgres -d postgres --no-psqlrc -c "
select tablename, policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and tablename in ('payments','complaints','users','audit_log','roles_permissions')
 order by tablename, policyname;"
```

*Expected*: no `p0_admin_all` on `payments`, `complaints`, `audit_log`, `roles_permissions`; and
`payments_admin_select`, `audit_log_admin_select`, `roles_permissions_admin_select` present.

---

### Gate 5 — Multi-session concurrency

`dblink` is **available but not installed**; the suite installs it itself. `pg_background` is not
available in this image at all.

```bash
docker exec -i supabase_db_church psql -U postgres -d postgres \
  -v ON_ERROR_STOP=1 --no-psqlrc < supabase/tests/0053_concurrency_test.sql
```

*Expected*: exactly one of two simultaneous `book_slot` calls on a one-seat slot succeeds and the
other raises `SLOT_FULL`; `apply_payment` racing `expire_stale_bookings` leaves the settled booking
untouched (`SKIP LOCKED` skips it rather than cancelling it); concurrent
`claim_event_outbox_batch` calls never return the same row twice.

Confirm `dblink` `EXECUTE` did not leak:

```bash
docker exec -i supabase_db_church psql -U postgres -d postgres --no-psqlrc -c "
select proname, proacl from pg_proc
 where proname like 'dblink%' and proacl::text ~ '(anon|authenticated)';"
```

*Expected*: 0 rows. `dblink` opens outbound connections and must stay `postgres`-only.

---

### Gate 6 — Arabic error contract over HTTP

```bash
curl -s -o /tmp/gate6.json -w '%{http_code}\n' \
  -X POST "http://127.0.0.1:54321/functions/v1/paymob-checkout" \
  -H "Content-Type: application/json" -d '{}'
cat /tmp/gate6.json
```

*Expected*: `401` with the frozen body

```json
{ "error": "UNAUTHORIZED", "message_ar": "يرجى تسجيل الدخول للمتابعة" }
```

A `500` or a connection reset here almost always means the Paymob placeholders above are missing and
the function failed to boot.

Repeat against the two newly authenticated cron endpoints, which currently accept **any**
unauthenticated caller:

```bash
for fn in reconcile-payments event-dispatcher; do
  printf '%s ' "$fn"
  curl -s -o /dev/null -w '%{http_code}\n' -X POST \
    "http://127.0.0.1:54321/functions/v1/$fn" -H "Content-Type: application/json" -d '{}'
done
```

*Expected*: `401` from both.

---

### Gate 7 — End-to-end book & pay

```bash
[ -f package.json ] && npm install
node supabase/e2e/book_pay_flow.mjs
```

The root `package.json` added by this feature declares only `@supabase/supabase-js`, which is what the
script imports. *Expected*: the flow completes, or halts with an explicit staging-configuration notice
when the out-of-band `TEST_*` and Paymob staging secrets are absent — not a module-resolution error.

---

### Gate 8 — Repository hygiene

```bash
echo '— CONCURRENTLY in migrations (must be empty)'
grep -rn 'CONCURRENTLY' supabase/migrations/ || true

echo '— residual video references (must be empty)'
grep -rniE 'video_purchases|purchase_video|apply_video_payment|deliver_personal_video|youtube-expiry|video_ready' \
  supabase/ apps/ || true

echo '— residual PRIEST references (must be empty)'
grep -rn 'PRIEST' supabase/ apps/ AGENTS.md || true

echo '— GRANT ALL in migrations (must be empty)'
grep -rn 'GRANT ALL' supabase/migrations/ || true

echo '— hardcoded secrets in functions (must be empty)'
grep -rniE 'secret_key|sk_live|service_role_key\s*=\s*["'"'"']' supabase/functions/ || true

echo '— youtube-expiry cron must be unscheduled'
docker exec -i supabase_db_church psql -U postgres -d postgres --no-psqlrc -c \
  "select jobid, jobname, schedule, command from cron.job where command ilike '%youtube%';"
```

*Expected*: every scan empty, and the `cron.job` query returns 0 rows. jobid 4 (`0 4 * * *`) currently
POSTs to `/functions/v1/youtube-expiry` and will keep firing daily at a dead endpoint unless 0053
unschedules it.

Also confirm the dropped objects are gone and the new ones exist:

```bash
docker exec -i supabase_db_church psql -U postgres -d postgres --no-psqlrc -c "
select 'remaining_capacity' as obj, count(*) from information_schema.columns
   where table_name='service_slots' and column_name='remaining_capacity'
union all select 'videos tables', count(*) from information_schema.tables
   where table_schema='public' and table_name in ('videos','video_purchases')
union all select 'payments.video_id', count(*) from information_schema.columns
   where table_name='payments' and column_name='video_id'
union all select 'outbox claimed_at+last_error', count(*) from information_schema.columns
   where table_name='event_outbox' and column_name in ('claimed_at','last_error')
union all select 'SUPER_ADMIN label', count(*) from pg_enum e join pg_type t on t.oid=e.enumtypid
   where t.typname='app_role' and e.enumlabel='SUPER_ADMIN'
union all select 'book_slot overloads', count(*) from pg_proc where proname='book_slot';"
```

*Expected*: `remaining_capacity` 0, `videos tables` 0, `payments.video_id` 0,
`outbox claimed_at+last_error` 2, `SUPER_ADMIN label` 1, `book_slot overloads` 1.

Finally, pin the `v_available_slots` contract — the view is deliberately **not** rewritten by this
feature, and six Dart files plus five widget tests depend on its exact column names:

```bash
docker exec -i supabase_db_church psql -U postgres -d postgres --no-psqlrc -c "
select column_name from information_schema.columns
 where table_name='v_available_slots' order by ordinal_position;"
```

*Expected*: `slot_id, service_id, title_ar, starts_at, ends_at, capacity, price, location,
booked_count, available_seats, slot_status`.
