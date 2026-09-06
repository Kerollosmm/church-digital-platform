# Testing Patterns & Verification Guide

## 1. The pgTAP / psql False-Green Trap
In PostgreSQL / pgTAP testing under this repository setup:
- Assertions wrapped in `PERFORM ok(...)` or `PERFORM is(...)` inside `DO $$ ... $$` blocks return text lines that `PERFORM` silently discards.
- `SELECT * FROM finish()` outputs diagnostic rows (e.g. `# Looks like you failed 1 test of 2`), but `psql` exits with code `0`.
- **Rule**: Automated test runners and human reviewers must NEVER trust exit code `0` alone. Always grep test stdout for `not ok` and `# Looks like you failed`.

## 2. Running SQL Test Suites
Because `/tests` is not mounted into the Docker container and `run_all.sql` uses `\ir` relative paths that fail over stdin, execute SQL suites individually:

```bash
# Executing individual test files
docker exec -i supabase_db_church psql -U postgres -d postgres < supabase/tests/0001_schema_test.sql
docker exec -i supabase_db_church psql -U postgres -d postgres < supabase/tests/0053_security_fixes_test.sql
docker exec -i supabase_db_church psql -U postgres -d postgres < supabase/tests/0053_concurrency_test.sql
```

## 3. Concurrency & Multi-Session Testing (`dblink`)
- Concurrency test suites (e.g. `0053_concurrency_test.sql`) simulate multiple concurrent client sessions using `dblink`.
- **Isolation Rule**:
  - The `dblink` extension must be installed in an isolated schema (e.g. `dblink_test`), never `public`.
  - Grants on `dblink_test` must be revoked from `PUBLIC`, `anon`, and `authenticated` to prevent privilege escalation.
- **Statements Execution**:
  - Multi-session commands returning rows (`SELECT ... FOR UPDATE`) or RPCs (`apply_payment`) must be wrapped in `DO $b$ ... $b$` blocks to prevent `dblink_exec` errors.
- **Listen / Notify Testing**:
  - `dblink_get_notify` must be polled with a bounded loop (50 x 100ms) to allow libpq time to process asynchronous events before asserting payloads.
- **Transaction Cleanliness**:
  - Exception blocks in dblink tests must issue `ROLLBACK` on active dblink connections to avoid leaving open transactions and uncommitted dirty state across test runs.

## 4. Full Quality Gate Verification Checklist

1. **Database Reset**: `npx supabase db reset` (applies 0001 -> 0053 + seed.sql with 0 errors).
2. **SQL Tests**: 45/45 suites passing via stdin (0 failure markers).
3. **Edge Functions**: `deno test --allow-env --allow-net supabase/functions/` (84 tests PASS).
4. **Mobile App**:
   - `cd apps/mobile && flutter analyze` (0 issues).
   - `cd apps/mobile && flutter test` (82 tests PASS).
5. **Admin App**:
   - `cd apps/admin && flutter analyze` (0 issues).
   - `cd apps/admin && flutter test` (45 tests PASS).
6. **Edge Runtime Perimeter**: `npx supabase functions serve` -> curl endpoints -> verify 401 with frozen Arabic JSON.
