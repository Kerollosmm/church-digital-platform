# Prod Drift Purge (Round 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every HIGH finding from the external review (H-1/H-2/H-3) and the one user-facing functional bug (M-2) by reifying the single load-bearing prod drift (`v_services`), purging all remaining prod-only drift in one forward migration (0085), and fixing three small code/doc issues.

**Architecture:** One idempotent forward migration that (a) creates what prod has but the repo lacks (`v_services` view, `complaints_admin_assign` policy), and (b) drops what prod has but the repo doesn't (17 functions, 5 payments columns, 10 tables, 5 enums, 1 policy) — every drop is `IF EXISTS`, so the migration is a no-op on fresh local resets. Plus three pinpoint code fixes in edge functions, one doc fix, and one smoke-script check.

**Tech Stack:** PostgreSQL 16 (Supabase), pgTAP, Deno edge functions (TypeScript), `@std/assert` tests with in-memory FakeClient.

**Spec:** Self-contained — scope approved 2026-09-06 ("lean round 3 + full drift purge"). Drift inventory was verified by full `comm` diff of a fresh prod schema dump (post-0084) against the local reset container. Findings H-1/H-2/H-3, M-1/M-2, L-4 from `review-2026-09-05.md` (Genspark).

## Global Constraints

- **Forward-only migrations**: never edit `supabase/migrations/0001..0084`. New migration is `0085_prod_drift_purge.sql`.
- **Prod project ref**: `qksgphryemrdrkwaqnxp` (linked as church-app). **NEVER touch staging ref `vkognohmnqxzegxqhvmm`**.
- **Executor does NOT commit.** Implement, run gates, stop. The orchestrator (Claude) reviews the diff, commits, and deploys (Task 8).
- **No PII in repo files**: phone numbers must never appear in source, tests, or docs. Use `+201000000000` (clearly fake) in tests.
- **Money is integer piastres**, never floats/decimals.
- **Arabic-only** user-facing strings.
- **pgTAP false-green trap**: a suite can exit 0 while assertions fail. Always grep output for `not ok` / `# Looks like you failed` / `ERROR:` — never trust the exit code alone. (`scripts/test-sql.js` already does this grepping itself.)
- **No secrets** are printed, logged, or persisted. Keys are passed via env/args only.
- Postgres enum labels **cannot be dropped** — the extra `booking_status` labels on prod (SUBMITTED, REJECTED, PARTIALLY_PAID, PAID) are accepted residual drift; do NOT try to remove them.
- Local truth: `npx supabase db reset` (container `supabase_db_church`) must replay 85/85 migrations cleanly. Local DB must equal repo migrations exactly.

---

### Task 1: Migration 0085 — reify v_services + purge prod drift

**Files:**
- Create: `supabase/migrations/0085_prod_drift_purge.sql`

**Interfaces:**
- Produces: `public.v_services` view (columns: `id bigint, title_ar text, description text, location text, next_slot_starts_at timestamptz, price_from integer, tenant_id bigint`) — consumed by the mobile app's booking home screen and by the updated smoke script (Task 6).
- Produces: policy `complaints_admin_assign` on `public.complaints` (replaces drifted `complaints assign write`).
- Removes: all drift objects listed below. Repo function `admin_record_cash_payment(uuid, bigint, text)` is KEPT (repo-clean, called by `apps/admin/lib/features/bookings/event_bookings_admin_repository.dart:260`); only the two bigint-keyed drift overloads are dropped.

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/0085_prod_drift_purge.sql` with EXACTLY this content:

```sql
-- 0085: prod drift purge + reify v_services
-- Prod predates the migration baseline (history partially "repaired" without
-- executing), so objects that later migrations were supposed to drop/create
-- diverged. Verified 2026-09-06 by full schema diff (prod dump post-0084 vs
-- local reset). Every drop is IF EXISTS -> no-op on fresh local resets.
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
--    whatsapp_outbox/refund_requests rows were already migrated by 0027.
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
```

- [ ] **Step 2: Verify it replays cleanly on a fresh reset**

Run: `npx supabase db reset`
Expected: all 85 migrations replay with no errors. (The 17 drops, 10 table drops, 5 type drops, and cron guard are all no-ops locally; `v_services` + policy + ALTERs apply.)

- [ ] **Step 3: Sanity-check v_services exists locally**

Run: `docker exec supabase_db_church psql -U postgres -d postgres -c "select column_name, data_type from information_schema.columns where table_schema='public' and table_name='v_services' order by ordinal_position;"`
Expected: 7 rows — id (bigint), title_ar (text), description (text), location (text), next_slot_starts_at (timestamp with time zone), price_from (integer), tenant_id (bigint).

- [ ] **Step 4: Sanity-check payments columns**

Run: `docker exec supabase_db_church psql -U postgres -d postgres -c "select column_name from information_schema.columns where table_schema='public' and table_name='payments' order by ordinal_position;"`
Expected exactly: id, booking_id, gateway_ref, amount, status, tenant_id, created_at, updated_at, deleted_at, merchant_order_id.

---

### Task 2: pgTAP regression test for 0085

**Files:**
- Create: `supabase/tests/0085_prod_drift_purge_test.sql`
- Modify: `supabase/tests/run_all.sql` (append one `\ir` line)

**Interfaces:**
- Consumes: Task 1's migration (must have been applied by `db reset`).

- [ ] **Step 1: Write the test file**

Create `supabase/tests/0085_prod_drift_purge_test.sql` with EXACTLY this content (44 checks):

```sql
BEGIN;
SELECT plan(44);

-- v_services reified
SELECT has_view('public', 'v_services', 'v_services view exists');
SELECT has_column('public', 'v_services', 'next_slot_starts_at', 'v_services.next_slot_starts_at exists');
SELECT has_column('public', 'v_services', 'price_from', 'v_services.price_from exists');
SELECT has_column('public', 'v_services', 'tenant_id', 'v_services.tenant_id exists');

-- drift tables gone
SELECT hasnt_table('public', 'alerts', 'alerts dropped');
SELECT hasnt_table('public', 'attendance', 'attendance dropped');
SELECT hasnt_table('public', 'clergy_profiles', 'clergy_profiles dropped');
SELECT hasnt_table('public', 'family_members', 'family_members dropped');
SELECT hasnt_table('public', 'households', 'households dropped');
SELECT hasnt_table('public', 'members', 'members dropped');
SELECT hasnt_table('public', 'visits', 'visits dropped');
SELECT hasnt_table('public', 'refund_requests', 'refund_requests dropped');
SELECT hasnt_table('public', 'venues', 'venues dropped');
SELECT hasnt_table('public', 'whatsapp_outbox', 'whatsapp_outbox dropped');

-- drift functions gone
SELECT hasnt_function('public', 'admin_apply_pastoral_fee_waiver', ARRAY['bigint','bigint','text','text'], 'admin_apply_pastoral_fee_waiver dropped');
SELECT hasnt_function('public', 'assign_clergy_to_event', ARRAY['bigint','bigint'], 'assign_clergy_to_event dropped');
SELECT hasnt_function('public', 'book_family_slots', ARRAY['bigint','bigint[]','boolean'], 'book_family_slots dropped');
SELECT hasnt_function('public', 'cancel_event_booking', ARRAY['bigint','text'], 'cancel_event_booking dropped');
SELECT hasnt_function('public', 'get_clergy_daily_itinerary', ARRAY['bigint','date'], 'get_clergy_daily_itinerary dropped');
SELECT hasnt_function('public', 'manage_family_members', ARRAY['text','bigint','text','text','text','date','text'], 'manage_family_members dropped');
SELECT hasnt_function('public', 'rapid_emergency_funeral_booking', ARRAY['text','text','bigint','bigint','timestamptz','integer','text'], 'rapid_emergency_funeral_booking dropped');
SELECT hasnt_function('public', 'record_cash_payment', ARRAY['bigint','integer','text'], 'record_cash_payment dropped');
SELECT hasnt_function('public', 'set_updated_at', ARRAY[]::text[], 'set_updated_at dropped');
SELECT hasnt_function('public', 'superadmin_create_extra_service', ARRAY['text','text','text','text','text','bigint','boolean','integer'], 'superadmin_create_extra_service dropped');
SELECT hasnt_function('public', 'superadmin_link_service_to_event_type', ARRAY['bigint','bigint','boolean'], 'superadmin_link_service_to_event_type dropped');
SELECT hasnt_function('public', 'superadmin_toggle_extra_service_status', ARRAY['bigint','boolean'], 'superadmin_toggle_extra_service_status dropped');
SELECT hasnt_function('public', 'superadmin_update_extra_service', ARRAY['bigint','text','text','text','text','text','bigint','boolean','integer'], 'superadmin_update_extra_service dropped');
SELECT hasnt_function('public', 'superadmin_upsert_event_type', ARRAY['bigint','text','bigint','boolean'], 'superadmin_upsert_event_type dropped');
SELECT hasnt_function('public', 'superadmin_upsert_extra_service', ARRAY['bigint','text','bigint','boolean','boolean'], 'superadmin_upsert_extra_service dropped');
SELECT hasnt_function('public', 'admin_record_cash_payment', ARRAY['bigint','integer','text','text'], 'admin_record_cash_payment(bigint,integer,text,text) dropped');
SELECT hasnt_function('public', 'admin_record_cash_payment', ARRAY['bigint','bigint','text','text'], 'admin_record_cash_payment(bigint,bigint,text,text) dropped');

-- payments drift columns gone
SELECT hasnt_column('public', 'payments', 'event_booking_id', 'payments.event_booking_id dropped');
SELECT hasnt_column('public', 'payments', 'method', 'payments.method dropped');
SELECT hasnt_column('public', 'payments', 'recorded_by', 'payments.recorded_by dropped');
SELECT hasnt_column('public', 'payments', 'received_at', 'payments.received_at dropped');
SELECT hasnt_column('public', 'payments', 'receipt_reference', 'payments.receipt_reference dropped');

-- drift enums gone
SELECT hasnt_type('public', 'alert_type', 'alert_type dropped');
SELECT hasnt_type('public', 'attendance_method', 'attendance_method dropped');
SELECT hasnt_type('public', 'member_status', 'member_status dropped');
SELECT hasnt_type('public', 'payment_method', 'payment_method dropped');
SELECT hasnt_type('public', 'pricing_mode', 'pricing_mode dropped');

-- complaints policy: repo version present, drift version absent
SELECT is(
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'complaints'
      AND policyname = 'complaints_admin_assign'),
  1::bigint,
  'complaints_admin_assign policy exists'
);
SELECT is(
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'complaints'
      AND policyname = 'complaints assign write'),
  0::bigint,
  'drift policy complaints assign write dropped'
);

-- H-3: all 19 functions carry the hardened search_path
WITH expected(sig, sp) AS (VALUES
  ('admin_pin_status()', 'search_path=public, extensions, pg_temp'),
  ('cancel_booking(bigint)', 'search_path=public, pg_temp'),
  ('complete_booking(bigint)', 'search_path=public, pg_temp'),
  ('confirm_booking(bigint)', 'search_path=public, pg_temp'),
  ('decrypt_complaint(bigint)', 'search_path=public, extensions, pg_temp'),
  ('emergency_override(bigint,bigint,boolean)', 'search_path=public, pg_temp'),
  ('enqueue_fcm_booking_status_push()', 'search_path=public, pg_temp'),
  ('expire_stale_bookings()', 'search_path=public, pg_temp'),
  ('join_waiting_list(bigint)', 'search_path=public, pg_temp'),
  ('manual_book(bigint,text,boolean,text)', 'search_path=public, pg_temp'),
  ('materialize_analytics()', 'search_path=public, pg_temp'),
  ('promote_waiting_list(bigint)', 'search_path=public, pg_temp'),
  ('reset_admin_pin(uuid)', 'search_path=public, extensions, pg_temp'),
  ('set_admin_pin(text)', 'search_path=public, extensions, pg_temp'),
  ('submit_complaint_secure(text,text)', 'search_path=public, extensions, pg_temp'),
  ('sync_offline_mutations(jsonb)', 'search_path=public, extensions, pg_temp'),
  ('transition_booking_status(bigint,booking_status,text,text,jsonb)', 'search_path=public, pg_temp'),
  ('update_fcm_token(text)', 'search_path=public, pg_temp'),
  ('verify_admin_pin(text)', 'search_path=public, extensions, pg_temp')
)
SELECT is(
  (SELECT count(*)
   FROM expected e
   JOIN pg_proc p ON p.oid = ('public.' || e.sig)::regprocedure
   WHERE e.sp = ANY (p.proconfig)),
  19::bigint,
  'all 19 SECURITY DEFINER functions carry hardened search_path'
);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Register the suite in run_all.sql**

Append to `supabase/tests/run_all.sql` (after the `0083_money_piastres_test.sql` line):

```sql
\ir 0085_prod_drift_purge_test.sql
```

- [ ] **Step 3: Run the SQL suite**

Run: `node scripts/test-sql.js`
Expected: `TOTAL SUITES: 73 | PASSED: 73 | FAILED: 0` (auto-discovery picks up the new file; `scripts/test-sql.js` greps for TAP failure markers itself). If anything fails, output shows `not ok N` lines — fix before proceeding.

---

### Task 3: M-1 — analytics-export dynamic CORS

**Files:**
- Modify: `supabase/functions/analytics-export/index.ts` (line 4 import; ~line 104 response headers)
- Test: `supabase/functions/analytics-export/index_test.ts` (append one test)

**Interfaces:**
- Consumes: `getCorsHeaders(req: Request): Record<string, string>` from `../_shared/http.ts` (reflects the request's `Origin` header when allowed, else the first allowed origin; always adds `Vary: Origin`).

- [ ] **Step 1: Write the failing test**

Append to `supabase/functions/analytics-export/index_test.ts`:

```ts
Deno.test("analytics-export: CSV response reflects allowed request origin (dynamic CORS)", async () => {
  const { deps } = createDeps();
  const req = new Request("https://x/analytics-export?report=utilization", {
    method: "GET",
    headers: { Authorization: "Bearer valid-token", Origin: "http://localhost:54321" },
  });
  const res = await handleRequest(req, deps);
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "http://localhost:54321");
  assertEquals(res.headers.get("Vary"), "Origin");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test --allow-env --allow-net supabase/functions/analytics-export/`
Expected: FAIL — the success path uses the module-load snapshot `corsHeaders`, whose `Access-Control-Allow-Origin` is `http://localhost:3000` (or the env default), not the request origin, and has no per-request reflection.

- [ ] **Step 3: Apply the fix**

In `supabase/functions/analytics-export/index.ts`:

Change line 4 from:
```ts
import { auth, respond, corsHeaders } from "../_shared/http.ts";
```
to:
```ts
import { auth, respond, getCorsHeaders } from "../_shared/http.ts";
```

Change the CSV success response (currently spreading the static `...corsHeaders`) to:
```ts
  return new Response(buildCsv(headers, rows), {
    headers: {
      ...getCorsHeaders(req),
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="${report}-${month}.csv"`,
    },
  });
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test --allow-env --allow-net supabase/functions/analytics-export/`
Expected: all tests PASS (existing tests don't assert CORS on the CSV path, so nothing else changes).

---

### Task 4: M-2 — diagnostic-engine alert fix (env phone + dispatcher-compatible payload)

The current code hardcodes an admin phone (PII in repo) and enqueues a `admin_security_alert` payload WITHOUT a `params` key — the dispatcher (`event-dispatcher/index.ts` TEMPLATES: `admin_security_alert: { paramCount: 2 }`) reads `payload.params`, so the alert can never render and is always dropped as failed.

**Files:**
- Modify: `supabase/functions/diagnostic-engine/index.ts`
- Test: `supabase/functions/diagnostic-engine/index_test.ts` (append two tests)
- Modify: `workflows/diagnostic_audit_loop.md` (scrub hardcoded phones, reference env var)

**Interfaces:**
- Produces: `DiagnosticDeps.alertPhone?: string` (injected in tests; falls back to `Deno.env.get("DIAGNOSTIC_ALERT_PHONE")`).
- Produces: outbox rows with payload shape `{ phone: string, template_name: "admin_security_alert", params: { param1: string, param2: string } }` — consumed by event-dispatcher's `sendWhatsApp`.

- [ ] **Step 1: Write the failing tests**

In `supabase/functions/diagnostic-engine/index_test.ts`, change line 1 from:
```ts
import { assertEquals } from "jsr:@std/assert";
```
to:
```ts
import { assertEquals, assertStringIncludes } from "jsr:@std/assert";
```

Then append:

```ts
Deno.test("diagnostic-engine: enqueues admin alert with dispatcher-compatible params", async () => {
  const fake = new FakeClient(["users", "bookings", "event_outbox"]);
  fake.seed("users", [{ id: "admin-1", role: "ADMIN" }]);
  const req = new Request("https://x/functions/v1/diagnostic-engine", {
    method: "POST",
    headers: { Authorization: "Bearer admin-token" },
  });
  const res = await handleRequest(req, {
    client: fake,
    serviceClient: fake,
    anonClient: fake,
    getUser: () => Promise.resolve({ data: { user: { id: "admin-1" } as any }, error: null }),
    alertPhone: "+201000000000",
  });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.critical_count, 3);
  const rows = fake.tableRows("event_outbox");
  assertEquals(rows.length, 1);
  assertEquals(rows[0].handler_type, "WHATSAPP");
  const payload = rows[0].payload as Record<string, unknown>;
  assertEquals(payload.phone, "+201000000000");
  assertEquals(payload.template_name, "admin_security_alert");
  const params = payload.params as Record<string, string>;
  assertEquals(params.param1, "3");
  assertStringIncludes(params.param2, "Anonymous SELECT permitted");
});

Deno.test("diagnostic-engine: alert skipped when no alert phone configured", async () => {
  Deno.env.delete("DIAGNOSTIC_ALERT_PHONE");
  const fake = new FakeClient(["users", "bookings", "event_outbox"]);
  fake.seed("users", [{ id: "admin-1", role: "ADMIN" }]);
  const req = new Request("https://x/functions/v1/diagnostic-engine", {
    method: "POST",
    headers: { Authorization: "Bearer admin-token" },
  });
  const res = await handleRequest(req, {
    client: fake,
    serviceClient: fake,
    anonClient: fake,
    getUser: () => Promise.resolve({ data: { user: { id: "admin-1" } as any }, error: null }),
  });
  assertEquals(res.status, 200);
  assertEquals(fake.tableRows("event_outbox").length, 0);
});
```

(Test rationale for `critical_count: 3`: the anon FakeClient sees seeded `users` rows → RLS-LEAK-USERS; the anon `bookings` insert succeeds → RLS-LEAK-BOOKINGS-WRITE; the fake `book_slot` RPC returns no error → RPC-AUTH-LEAK-BOOK-SLOT.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test --allow-env --allow-net supabase/functions/diagnostic-engine/`
Expected: FAIL — first new test: no `alertPhone` dep exists, `ADMIN_PHONE` is hardcoded (payload has no `params`, wrong phone); second new test: outbox gets 1 row (alert always fires).

- [ ] **Step 3: Apply the fix**

In `supabase/functions/diagnostic-engine/index.ts`:

(a) Delete line 4:
```ts
const ADMIN_PHONE = "<redacted admin phone>";
```

(b) Add `alertPhone` to the deps interface:
```ts
export interface DiagnosticDeps {
  serviceClient?: any;
  anonClient?: any;
  getUser?: (token: string) => Promise<{ data: { user: any } | null; error: any }>;
  client?: any;
  alertPhone?: string;
}
```

(c) Inside `handleRequest`, right after the `authRes` guard, resolve the phone:
```ts
  const alertPhone =
    deps?.alertPhone ??
    (typeof Deno !== "undefined" ? Deno.env.get("DIAGNOSTIC_ALERT_PHONE") : undefined) ??
    "";
```

(d) Replace the alert dispatch block (currently `if (criticals.length > 0) { ... }` inserting a payload without `params`) with:
```ts
    if (criticals.length > 0 && alertPhone !== "") {
      await serviceClient.from("event_outbox").insert({
        handler_type: "WHATSAPP",
        payload: {
          phone: alertPhone,
          template_name: "admin_security_alert",
          params: {
            param1: String(criticals.length),
            param2: criticals.map((c: any) => c.title).join("; "),
          },
          timestamp: new Date().toISOString(),
        },
        status: "PENDING",
      });
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test --allow-env --allow-net supabase/functions/diagnostic-engine/`
Expected: all 5 tests PASS (3 existing + 2 new).

- [ ] **Step 5: Scrub PII from the workflow doc**

In `workflows/diagnostic_audit_loop.md`:

Change line 6 from:
```markdown
- **Primary Operator Phone:** `<redacted admin phone>` (Admin).
```
to:
```markdown
- **Primary Operator:** Admin (alert phone configured via the `DIAGNOSTIC_ALERT_PHONE` env secret on the function).
```

Delete line 7 (`- **Secondary Identity:** `<redacted parishioner phone>` (Parishioner).`).

Change line 46 from:
```markdown
     1. **WhatsApp Alert (Admin Phone: `<redacted admin phone>`):**
```
to:
```markdown
     1. **WhatsApp Alert (Admin Phone via `DIAGNOSTIC_ALERT_PHONE`):**
```

- [ ] **Step 6: Verify no PII remains**

Run: `git grep -n -E "20(12|10)\d{7}" -- supabase/functions workflows apps memory-bank docs scripts`
Expected: no matches. (Also confirm no real phone number appears anywhere except the fake `+201000000000` in tests.)

---

### Task 5: L-4 — remove deleted offline-sync from architecture diagram

**Files:**
- Modify: `memory-bank/systemPatterns.md` (line 22)

- [ ] **Step 1: Remove the stale line**

Delete this line from the Edge Functions box in `memory-bank/systemPatterns.md`:
```text
│  │ • offline-sync                                   │  │
```
(The `offline-sync` edge function was deleted from prod; only `event-dispatcher`, `otp-sms`, `diagnostic-engine`, `analytics-export` remain.)

---

### Task 6: Smoke script gains v_services check

**Files:**
- Modify: `scripts/staging-smoke.mjs` (Check 2, after the `audit_log` block, before the `sunday_school_classes` block)

**Interfaces:**
- Consumes: `public.v_services` from Task 1 (reachable via REST at `/rest/v1/v_services` because Task 1 grants `service_role`).

- [ ] **Step 1: Add the check**

Insert into Check 2 (after the `auditRes` block, before the `sundayRes` block):

```js
  // v_services view present (mobile booking home screen reads it)
  const vServicesRes = await fetch(`${url}/rest/v1/v_services?limit=0`, {
    headers: getHeaders(serviceKey)
  });
  if (vServicesRes.status !== 200) {
    const text = await vServicesRes.text();
    return {
      pass: false,
      detail: `v_services query returned HTTP ${vServicesRes.status} (expected 200) | ${snippet(text)}`
    };
  }
```

Also update Check 2's final success detail string from:
```js
    detail: `Tables present, columns verified, sunday_school_classes absent (HTTP ${sundayRes.status})`
```
to:
```js
    detail: `Tables present, columns verified, v_services present, sunday_school_classes absent (HTTP ${sundayRes.status})`
```

- [ ] **Step 2: Verify the script still parses**

Run: `node --check scripts/staging-smoke.mjs`
Expected: no output (syntax OK).

---

### Task 7: Full local gate run

**Files:** none (verification only)

- [ ] **Step 1: db reset replay**

Run: `npx supabase db reset`
Expected: 85/85 migrations replay, no errors. Retry once if the storage container is slow to start (known infra hiccup).

- [ ] **Step 2: pgTAP suite**

Run: `node scripts/test-sql.js`
Expected: `TOTAL SUITES: 73 | PASSED: 73 | FAILED: 0`.

- [ ] **Step 3: Deno edge function tests**

Run: `deno test --allow-env --allow-net supabase/functions/`
Expected: all tests pass (was 75 before; +1 analytics-export, +2 diagnostic-engine).

- [ ] **Step 4: Report and stop**

Do NOT commit. Do NOT push. Do NOT touch the prod project. Leave the working tree dirty for orchestrator review.

---

### Task 8: ORCHESTRATOR-ONLY — review, commit, data check, push, redeploy, smoke

**Executor (agy) must NOT perform this task.** Performed by Claude after reviewing the diff and re-running all Task 7 gates independently.

- [ ] **Step 1: Review the full diff** (`git diff` + `git status`) against this plan; re-run Task 7 gates.

- [ ] **Step 2: Commit** (one or two commits, e.g. `feat(db): 0085 prod drift purge + v_services reify` and `fix(functions): dynamic CORS + diagnostic alert payload`), including the smoke script, workflows doc, systemPatterns, memory-bank/activeContext.md update.

- [ ] **Step 3: Pre-push data check (STOP GATE).** Read-only row counts on PROD for the 10 tables being dropped:
  `alerts, attendance, clergy_profiles, family_members, households, members, visits, refund_requests, venues, whatsapp_outbox`.
  Use the REST API with the revealed service key (env/args only, never printed/persisted). **If ANY table holds rows, STOP and ask the user before pushing** — non-empty means live data the diff work assumed was migrated/legacy. (Empty tables are expected: they belong to a never-launched parallel implementation.)

- [ ] **Step 4: Push 0085 to prod.** `npx supabase db push` (linked project church-app / qksgphryemrdrkwaqnxp). If push reports conflicts from the migration-history repair era, resolve via Management API `db query` like round 2 — never `--force`-reset prod.

- [ ] **Step 5: Redeploy the two changed functions.**
  `npx supabase functions deploy analytics-export` and `npx supabase functions deploy diagnostic-engine` (project qksgphryemrdrkwaqnxp). Ask the user for the alert phone value and set `npx supabase secrets set DIAGNOSTIC_ALERT_PHONE=<user-supplied>` — never guess or hardcode it.

- [ ] **Step 6: Prod smoke.** Run `node scripts/staging-smoke.mjs` with prod URL + keys (env only). Expected 7/7, including the new v_services probe in Check 2.

- [ ] **Step 7: Verify drift is gone.** Re-dump prod schema (`pg_dump --schema-only` via Management API or `npx supabase db dump --schema public`) and confirm: 10 tables absent, 17 function signatures absent, 5 enums absent, `v_services` present, `complaints assign write` policy absent. Also check `cron.job` for leftover legacy jobs and report any stragglers.

- [ ] **Step 8: Update `memory-bank/activeContext.md`** with the round-3 completion milestone and commit.

---

## Self-Review

- Spec coverage: H-1 (drift purge) → Tasks 1-2; H-2 (drop parallel payments impl, not reify) → Task 1 §4-6; H-3 (search_path) → Task 1 §8 + Task 2 check; M-1 → Task 3; M-2 → Task 4; L-4 → Task 5; v_services reify → Task 1 §1 + Task 6. Deferred per approved lean decision: L-1, L-3, L-5, L-6, L-7, M-3..M-6, L-2.
- Placeholder scan: all code blocks are complete and verbatim; no TBD/TODO.
- Type consistency: `getCorsHeaders(req)` matches `_shared/http.ts:34`; `alertPhone` dep matches tests; `admin_record_cash_payment(uuid, bigint, text)` preserved everywhere; pgTAP `plan(44)` matches the check count (4 + 10 + 17 + 5 + 5 + 2 + 1 = 44).
