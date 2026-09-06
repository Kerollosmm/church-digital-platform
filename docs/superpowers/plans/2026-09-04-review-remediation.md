# Review Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all verified findings from the 2026-09-04 full-codebase review: fail-open auth gate, admin UI error deadlocks, SUPER_ADMIN export lockout, tenant/audit DB invariant breaches, orphaned event-booking mobile flow, and legacy EGP→piastres money unification.

**Architecture:** Part A (Tasks 1–6) is independently shippable client + DB invariant fixes. Part B (Tasks 7–9) is the high-risk money unification migration and its client/test sweep — it must land as a separate commit after Part A is green. One forward migration per DB concern (0081, 002, 0083) — never edit historical migrations; migrations replay 0001→0080 today and must continue replaying cleanly.

**Tech Stack:** Flutter/Dart (Riverpod, GoRouter), PostgreSQL 16 (Supabase, RLS, SECURITY DEFINER RPCs, pgTAP), Deno/TypeScript edge functions.

**Spec:** 2026-09-04 Gemini full-codebase review (result.json in `C:\Users\KimoStore\AppData\Local\Temp\delegate-relay\church-2026-09-04T16-22-51-021Z\`), verified against source by the orchestrator. Memory-bank: `memory-bank/security-invariants.md`, `memory-bank/techContext.md`.

## Global Constraints

- Never modify an existing migration file — only add new forward migrations (next numbers: 0081, 0082, 0083).
- All money integers are **piastres** (1 EGP = 100) after Task 8; strictly positive checks preserved.
- Arabic error contract: user-facing errors use Arabic text; codes limited to `UNAUTHORIZED | FORBIDDEN | BAD_REQUEST | UPSTREAM_ERROR | INTERNAL`.
- SECURITY DEFINER functions must `SET search_path = public, pg_temp` (public, extensions only where extension access is genuinely required — `sync_offline_mutations` keeps its current setting).
- Every RLS policy includes `tenant_id = public.tenant_id()` where the table has a tenant column.
- No `git add` / `git commit` by the implementer — the orchestrator commits after review.
- Gate commands (run these exact forms):
  - Mobile: `cd apps/mobile; flutter analyze; flutter test`
  - Admin: `cd apps/admin; flutter analyze; flutter test`
  - Edge: `deno test --allow-env --allow-net supabase/functions/`
  - DB single suite: `docker exec -i supabase_db_church psql -U postgres -d postgres < supabase/tests/<NNNN>_test.sql` then **grep stdout for `not ok` and `Looks like you failed`** — psql exit code lies (pgTAP false-green trap).
  - Full DB replay: `npx supabase db reset` (replays all migrations + seed), then re-run affected suites.

---

## Part A — Code & Invariant Fixes

### Task 1: Fail-closed `PhoneVerifyGate.checkSession`

**Files:**
- Modify: `apps/mobile/lib/core/auth/phone_verify_gate.dart:39-47`
- Test: `apps/mobile/test/features/auth/phone_verify_gate_test.dart`

**Interfaces:**
- Consumes: existing `PhoneVerifyGate.checkSession([bool Function()? isLoggedIn])`.
- Produces: same signature; only the no-callback exception fallback behavior changes (`true` → `false`). All existing callers (`ensureAuth`, `_PhoneVerifyGateState`) and test-injected `isLoggedIn` callbacks are unaffected.

- [ ] **Step 1: Write the failing test**

Add to `apps/mobile/test/features/auth/phone_verify_gate_test.dart` (inside the existing main test group; if no such group exists, create `void main() { test(...); }` with `package:flutter_test`):

```dart
test('checkSession fails closed when Supabase is not initialized', () {
  // In the test zone Supabase.instance throws (never initialized).
  // Injected callbacks remain authoritative when provided:
  expect(PhoneVerifyGate.checkSession(() => true), isTrue);
  expect(PhoneVerifyGate.checkSession(() => false), isFalse);
  // Uninitialized client must NOT be treated as logged in:
  expect(PhoneVerifyGate.checkSession(), isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile; flutter test test/features/auth/phone_verify_gate_test.dart`
Expected: FAIL — `checkSession()` returned `true`.

- [ ] **Step 3: Write minimal implementation**

In `apps/mobile/lib/core/auth/phone_verify_gate.dart`, replace the catch block of `checkSession` (lines 43–46) with:

```dart
    } catch (e, st) {
      debugPrint('Supabase session check failed, failing closed: $e\n$st');
      return false;
    }
```

Do not change the method signature, the `isLoggedIn != null` branch, or any other method.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile; flutter test test/features/auth/phone_verify_gate_test.dart`
Expected: PASS. Then run the full suite: `flutter test` — all 88+ tests PASS, `flutter analyze` — 0 issues.

- [ ] **Step 5: Commit checkpoint**

Leave changes uncommitted in the working tree; note in the report that Task 1 is complete. (Orchestrator commits.)

---

### Task 2: SUPER_ADMIN access to `analytics-export`

**Files:**
- Modify: `supabase/functions/analytics-export/index.ts:31-33`
- Test: `supabase/functions/analytics-export/index_test.ts`

**Interfaces:**
- Produces: `exportAllowed(role: string | undefined): boolean` — now `true` for `ADMIN` and `SUPER_ADMIN` (case-insensitive), `false` otherwise. No signature change.

- [ ] **Step 1: Write the failing test**

In `supabase/functions/analytics-export/index_test.ts`, find the existing `exportAllowed` test block and extend it (match the file's existing assert style — `assertEquals` from `std/assert`):

```ts
Deno.test("exportAllowed permits admins and super admins only", () => {
  assertEquals(exportAllowed("ADMIN"), true);
  assertEquals(exportAllowed("admin"), true);
  assertEquals(exportAllowed("SUPER_ADMIN"), true);
  assertEquals(exportAllowed("super_admin"), true);
  assertEquals(exportAllowed("USER"), false);
  assertEquals(exportAllowed(undefined), false);
});
```

Also check whether an HTTP-level test asserts 403 for a SUPER_ADMIN JWT/role — if one exists, update its expectation to 200.

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test --allow-env --allow-net supabase/functions/analytics-export/`
Expected: FAIL on the new `SUPER_ADMIN` assertions.

- [ ] **Step 3: Write minimal implementation**

Replace `exportAllowed` in `supabase/functions/analytics-export/index.ts:31-33`:

```ts
export function exportAllowed(role: string | undefined): boolean {
  const r = role?.toUpperCase();
  return r === "ADMIN" || r === "SUPER_ADMIN";
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test --allow-env --allow-net supabase/functions/`
Expected: all edge suites PASS (was 75/75 before; count may grow with new tests).

---

### Task 3: Admin `PaymentsAdminScreen` — kill the loading deadlock

**Files:**
- Modify: `apps/admin/lib/features/payments/payments_admin_screen.dart:12-48`
- Test: `apps/admin/test/features/payments/payments_admin_screen_test.dart` (extend the existing test file; if the file doesn't exist, create it following the sibling test conventions — mocked repo with `Either<Failure, T>` returns)

**Interfaces:**
- Consumes: `PaymentsAdminRepository.list()` returning `Future<Either<Failure, List<Map<String, dynamic>>>>`, `Failure` from `apps/admin/lib/core/result.dart`.
- Produces: screen renders an Arabic error banner on failure; no behavior contract change for the repo.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('shows Arabic error instead of infinite spinner on failure', (tester) async {
  final repo = _FailingPaymentsRepo(); // list() returns Left(Failure(code: 'INTERNAL', message: 'حدث خطأ في الاتصال بالخادم'))
  await tester.pumpWidget(MaterialApp(home: PaymentsAdminScreen(repo: repo)));
  await tester.pumpAndSettle();
  expect(find.text('حدث خطأ في الاتصال بالخادم'), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsNothing);
});
```

(`_FailingPaymentsRepo` is a minimal fake implementing `PaymentsAdminRepository` — copy the interface from `payments_admin_repository.dart`; every method other than `list()` can `throw UnimplementedError()`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/admin; flutter test test/features/payments/`
Expected: FAIL — spinner never resolves; error text not found.

- [ ] **Step 3: Write minimal implementation**

Rewrite the state class in `payments_admin_screen.dart` so `Left` becomes a Future error the `FutureBuilder` renders (do not use `unwrapOrThrow`; keep the repo's Either seam):

```dart
class _PaymentsAdminScreenState extends State<PaymentsAdminScreen> {
  late Future<List<Map<String, dynamic>>> _rows;

  @override
  void initState() {
    super.initState();
    _rows = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async =>
      (await widget.repo.list()).fold(
        (f) => throw f,
        (rows) => List<Map<String, dynamic>>.from(
          rows.map((r) => Map<String, dynamic>.from(r)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المدفوعات')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _rows,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final err = snapshot.error;
            final msg = err is Failure
                ? err.message
                : 'حدث خطأ غير متوقع، يرجى المحاولة لاحقاً';
            return Center(child: Text(msg));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              return ListTile(
                title: Text('دفع #${r['id']} — ${r['amount']} جنيه'),
                subtitle: Text('حجز ${r['booking_id']} — ${r['status']}'),
                trailing: Text(r['gateway_ref']?.toString() ?? ''),
              );
            },
          );
        },
      ),
    );
  }
}
```

(`throw f` inside an `async` function rejects the Future — that is the correct seam here. The sin being fixed is *throwing inside `setState`/`build`*, not throwing into a Future the `FutureBuilder` observes.)

- [ ] **Step 4: Run tests and analyze**

Run: `cd apps/admin; flutter test; flutter analyze`
Expected: all tests PASS (80+), 0 analyzer issues.

---

### Task 4: Admin `slots` / `faq` / `announcements` — no throws inside `setState`

**Files:**
- Modify: `apps/admin/lib/features/slots/slots_admin_screen.dart:12-35`
- Modify: `apps/admin/lib/features/content/faq_admin_screen.dart:11-34`
- Modify: `apps/admin/lib/features/content/announcements_admin_screen.dart:12-35`
- Test: extend each screen's existing test file under `apps/admin/test/` (create if missing, same fake-repo pattern as Task 3)

**Interfaces:**
- Consumes: each screen's existing repository (`SlotsAdminRepository.list()`, `ContentRepository.faq()`, `AnnouncementsRepository.list()`) returning `Either<Failure, ...>`.
- Produces: identical widget API; state gains a `String? _error` field rendered as an Arabic message.

- [ ] **Step 1: Write the failing tests (one per screen)**

For each of the three screens, add a test of the same shape:

```dart
testWidgets('shows Arabic error instead of crashing on load failure', (tester) async {
  final repo = _FailingRepo(); // repo.list() (or .faq()) returns Left(Failure(code: 'INTERNAL', message: 'حدث خطأ في الاتصال بالخادم'))
  await tester.pumpWidget(MaterialApp(home: SlotsAdminScreen(repo: repo)));
  await tester.pump();
  await tester.pump(); // allow setState round-trip
  expect(tester.takeException(), isNull); // no uncaught exception in widget pipeline
  expect(find.text('حدث خطأ في الاتصال بالخادم'), findsOneWidget);
});
```

Repeat for `FaqAdminScreen` (call `repository.faq()` in the fake) and `AnnouncementsAdminScreen`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/admin; flutter test`
Expected: FAIL — `takeException()` is non-null (Failure thrown through `setState`) on all three.

- [ ] **Step 3: Write minimal implementation**

In each of the three screens, apply the identical transformation. Add a field:

```dart
  String? _error;
```

Replace the `_load` body (currently `res.fold((f) => throw f, ...)`) with:

```dart
  Future<void> _load() async {
    final res = await widget.repo.list(); // faq_admin: widget.repository.faq()
    if (!mounted) return;
    setState(() {
      res.fold(
        (f) {
          _error = f.message;
          _rows = null;
        },
        (rows) {
          _error = null;
          _rows = List<Map<String, dynamic>>.from(
            rows.map((r) => Map<String, dynamic>.from(r)),
          );
        },
      );
      _loading = false;
    });
  }
```

In `build`, after the `_loading` branch, add an error branch before the list:

```dart
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              ),
            )
          : ListView.builder(
              // ... unchanged
```

Notes:
- Keep the `List<Map<String, dynamic>>.from(rows.map(...))` copy step in each screen — some fakes return immutable maps.
- `faq_admin_screen.dart` and `announcements_admin_screen.dart` have further methods (`_add`, `_create`) that also `fold((f) => throw f, ...)` inside `setState` or after `await showDialog`; apply the same conversion there: on `Left`, `setState(() => _error = f.message)` (or `ScaffoldMessenger.showSnackBar(SnackBar(content: Text(f.message)))` where no reload follows) — never `throw`.

- [ ] **Step 4: Run tests and analyze**

Run: `cd apps/admin; flutter test; flutter analyze`
Expected: all PASS, 0 issues.

---

### Task 5: Migration 0081 — `offline_sync_log` tenant hardening

**Files:**
- Create: `supabase/migrations/0081_offline_sync_tenant_hardening.sql`
- Test: `supabase/tests/0081_offline_sync_tenant_test.sql`

**Interfaces:**
- Produces: `public.offline_sync_log` gains `tenant_id bigint NOT NULL DEFAULT public.tenant_id()`; its SELECT policy gains the tenant predicate; `authenticated` loses direct write DML (granted by 0050). `sync_offline_mutations` keeps working — it inserts without naming `tenant_id`, so the column default applies.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/0081_offline_sync_tenant_test.sql`:

```sql
begin;
select plan(5);

select has_column('public', 'offline_sync_log', 'tenant_id',
  'offline_sync_log has tenant_id column');

select col_not_null('public', 'offline_sync_log', 'tenant_id',
  'offline_sync_log.tenant_id is NOT NULL');

select is(
  (select count(*) from pg_policies
    where schemaname = 'public'
      and tablename = 'offline_sync_log'
      and (qual like '%tenant_id%' or with_check like '%tenant_id%')),
  1::bigint,
  'offline_sync_log RLS policy checks tenant_id'
);

select is(
  (select has_table_privilege('authenticated', 'public.offline_sync_log', 'INSERT, UPDATE, DELETE')),
  false,
  'authenticated has no direct write DML on offline_sync_log'
);

select is(
  (select has_table_privilege('authenticated', 'public.offline_sync_log', 'SELECT')),
  true,
  'authenticated retains SELECT via read grant'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run test to verify it fails**

Run (Docker Desktop must be running; start `supabase_db_church` if stopped):
`docker exec -i supabase_db_church psql -U postgres -d postgres < supabase/tests/0081_offline_sync_tenant_test.sql 2>&1 | grep -E "not ok|failed|plan\("`
Expected: at least one `not ok` (column/policy/privilege assertions fail — migration 0081 doesn't exist yet). If Docker is unavailable, note it in the report and proceed — the migration itself is still required.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/0081_offline_sync_tenant_hardening.sql`:

```sql
-- 0081: offline_sync_log tenant invariant hardening
-- Closes the review finding: table lacked tenant_id and its RLS policy
-- lacked the tenant predicate; 0050 granted write DML to authenticated.

begin;

alter table public.offline_sync_log
  add column if not exists tenant_id bigint not null default public.tenant_id();

update public.offline_sync_log
  set tenant_id = public.tenant_id()
  where tenant_id is null;

drop policy if exists "Users can view own sync logs" on public.offline_sync_log;

create policy "Users can view own sync logs"
  on public.offline_sync_log
  for select
  to authenticated
  using (auth.uid() = user_id and tenant_id = public.tenant_id());

-- Revoke direct write DML granted in 0050; writes flow through
-- sync_offline_mutations RPC only.
revoke insert, update, delete on public.offline_sync_log from authenticated;

commit;
```

- [ ] **Step 4: Replay and run tests**

Run: `npx supabase db reset` (replays 0001→0081 + seed), then:
`docker exec -i supabase_db_church psql -U postgres -d postgres < supabase/tests/0081_offline_sync_tenant_test.sql 2>&1 | grep -E "not ok|Looks like"`
Expected: no `not ok` lines. Also re-run `supabase/tests/0032_offline_sync_test.sql` and `supabase/tests/0050_read_grants_test.sql` the same way — the offline-sync RPC behavior and read grants must still hold. **Grep stdout, don't trust exit codes.**

---

### Task 6: Migration 0082 — `audit_log.entity_uuid` + `apply_payment` search_path

**Files:**
- Create: `supabase/migrations/0082_audit_entity_uuid.sql`
- Test: `supabase/tests/0082_audit_entity_uuid_test.sql`

**Interfaces:**
- Produces: `public.audit_log.entity_uuid uuid` (nullable — legacy bigint rows keep `entity_id = 0` and their `meta.event_booking_id`). The four event-booking RPCs (recreated here) populate `entity_uuid`. `apply_payment` gets `set search_path = public, pg_temp`.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/0082_audit_entity_uuid_test.sql`:

```sql
begin;
select plan(4);

select has_column('public', 'audit_log', 'entity_uuid',
  'audit_log has entity_uuid column');

select is(
  (select proconfig::text from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'apply_payment'),
  (select proconfig::text from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'apply_payment'),
  'apply_payment exists (sanity)'
);

select is(
  position('pg_temp' in coalesce((select proconfig::text from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'apply_payment'), '')) > 0,
  true,
  'apply_payment search_path includes pg_temp'
);

-- functional: submitting an event booking records entity_uuid in audit_log
select is(
  (select count(*) from public.audit_log
    where action = 'submit_event_booking'
      and entity_type = 'event_bookings'
      and entity_uuid is not null)
  > (select count(*) from public.audit_log
    where action = 'submit_event_booking'
      and entity_type = 'event_bookings'
      and entity_uuid is not null),
  true,
  'sanity tautology (replaced by functional check below)'
);

select * from finish();
rollback;
```

The fourth check above is a placeholder tautology on purpose — replace it during implementation with a functional check: inside the transaction, create a test user (follow the pattern used in `supabase/tests/0074_event_booking_rpcs_test.sql` for creating a user + calling `submit_event_booking`), call the RPC, then assert:

```sql
select is(
  (select count(*) from public.audit_log
    where action = 'submit_event_booking'
      and entity_type = 'event_bookings'
      and entity_uuid is not null),
  1::bigint,
  'submit_event_booking audit row records entity_uuid'
);
```

Copy the user/RPC fixtures verbatim from the 0074 test file — same IDs, same cleanup-on-rollback approach.

- [ ] **Step 2: Run test to verify it fails**

Run: `docker exec -i supabase_db_church psql -U postgres -d postgres < supabase/tests/0082_audit_entity_uuid_test.sql 2>&1 | grep -E "not ok|Looks like"`
Expected: failures — `entity_uuid` column missing, `apply_payment` proconfig lacks `pg_temp`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/0082_audit_entity_uuid.sql`. Structure:

```sql
-- 0082: audit_log UUID entity linkage + apply_payment search_path hardening
begin;

alter table public.audit_log
  add column if not exists entity_uuid uuid;

-- apply_payment: re-created verbatim from 0071 with only the
-- search_path corrected (public, pg_temp).
create or replace function public.apply_payment(p_payment_id bigint)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
-- BODY: copy the entire body from migration 0071_review_fixes.sql
-- (lines 244-274) verbatim. Do not change a single statement in the body.
$$;

revoke all on function public.apply_payment(bigint) from public, anon, authenticated;
grant execute on function public.apply_payment(bigint) to service_role;
```

(If 0071 already contains the revoke/grant block for `apply_payment`, keep the same grants — check 0071 after the function definition and copy those statements here.)

Then, for each of these four functions, **copy the complete latest definition** into 0082 and change **only** the `INSERT INTO public.audit_log` statement, adding `entity_uuid`:

| Function | Latest definition lives in | Audit insert site |
|---|---|---|
| `submit_event_booking` | `0074_event_booking_rpcs.sql` | lines ~164-175 |
| `admin_confirm_booking` | `0074_event_booking_rpcs.sql` | lines ~284-296 |
| `admin_reject_booking` | `0074_event_booking_rpcs.sql` | lines ~372-382 |
| `admin_quick_cash_collect` | `0078_operational_pivot.sql` (supersedes 0074's `admin_record_cash_payment`-era copy) | lines ~487-499 in 0074 / matching block in 0078 |

The audit insert becomes (example for `submit_event_booking`):

```sql
  INSERT INTO public.audit_log (user_id, action, entity_type, entity_id, entity_uuid, meta)
  VALUES (
    v_user,
    'submit_event_booking',
    'event_bookings',
    0,
    v_booking_id,
    jsonb_build_object(
      'event_type_id', p_event_type_id,
      'total_price_piastres', v_total_price
    )
  );
```

For `admin_confirm_booking` / `admin_reject_booking` / `admin_quick_cash_collect`, use the booking's UUID (`p_booking_id` or the variable holding it). Keep the existing `meta` jsonb unchanged. Append each function's original `revoke`/`grant` statements (from its source migration) after its re-creation. End the migration with `commit;`.

- [ ] **Step 4: Replay and run tests**

Run: `npx supabase db reset`, then pipe `0082_audit_entity_uuid_test.sql`, `0012_apply_payment_test.sql`, `0071_review_fixes_test.sql`, `0074_event_booking_rpcs_test.sql`, and `0078_operational_pivot_test.sql` through the docker-exec psql runner, grepping each for `not ok`.
Expected: all clean. The 0012/0071 suites prove `apply_payment` still behaves identically; 0074/0078 prove the event-booking RPCs still behave identically.

---

## Part B — Money Unification (legacy EGP → integer piastres)

> Lands as a separate commit after Part A. High-risk: run the FULL pgTAP sweep afterward.

### Task 7: Wire `EventBookingScreen` into the mobile router

**Files:**
- Modify: `apps/mobile/lib/services/app_routes.dart`
- Modify: `apps/mobile/lib/app_router.dart`
- Modify: `apps/mobile/lib/widgets/bottom_nav_scaffold.dart` (entry point)
- Test: `apps/mobile/test/` — extend router/navigation tests if any exist (search for `app_router` or `buildRouter` in `apps/mobile/test/`); otherwise extend `apps/mobile/test/screens/event_booking_screen_test.dart` with a route-level smoke test.

**Interfaces:**
- Consumes: `SupabaseEventBookingRepository({SupabaseClient? client})` (`apps/mobile/lib/repositories/supabase_event_booking_repository.dart:7`), `EventBookingScreen({required EventBookingRepository repository})`.
- Produces: named route `AppRoutes.eventBooking` at path `/event-booking`, reachable from the home hub.

- [ ] **Step 1: Add the route constant**

`apps/mobile/lib/services/app_routes.dart`:

```dart
abstract final class AppRoutes {
  static const paymentProof = 'payment-proof';
  static const familyArchive = 'family-archive';
  static const eventBooking = 'event-booking';
}
```

- [ ] **Step 2: Add the route and entry point**

In `apps/mobile/lib/app_router.dart`:

```dart
import 'repositories/supabase_event_booking_repository.dart';
import 'screens/event_booking_screen.dart';

GoRoute eventBookingRoute() {
  return GoRoute(
    path: '/event-booking',
    name: AppRoutes.eventBooking,
    builder: (context, state) => EventBookingScreen(
      repository: SupabaseEventBookingRepository(),
    ),
  );
}
```

Add `eventBookingRoute(),` to the `routes:` list in `buildRouter` (next to `paymentProofRoute(db)`).

In `apps/mobile/lib/widgets/bottom_nav_scaffold.dart`, `_buildHomeTab` currently exposes `onTapBooking: () => _switchTab(1)`. Add an event-booking entry: pass a new optional callback to `HomeHubScreen` — `onTapEventBooking: () => context.push('/event-booking')` — and add a matching card/tile in `HomeHubScreen` (labeled `حجز مناسبة خاصة`, placed next to the existing booking tile, reusing the existing tile widget and styling). Read `home_hub_screen.dart` first and follow its existing tile pattern exactly; the new tile's `onTap` calls the injected `onTapEventBooking` callback.

- [ ] **Step 3: Test**

Extend `apps/mobile/test/screens/event_booking_screen_test.dart` with:

```dart
testWidgets('event booking screen is reachable via named route', (tester) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => context.pushNamed(AppRoutes.eventBooking),
            child: const Text('go'),
          ),
        ),
      ),
      eventBookingRoute(),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  expect(find.byType(EventBookingScreen), findsOneWidget);
});
```

Adjust fakes so the repository passed to the route can be overridden for tests: change `eventBookingRoute()` to accept an optional `EventBookingRepository? repository` parameter defaulting to `SupabaseEventBookingRepository()`, and pass it through to the screen (the test passes its existing `FakeEventBookingRepository`).

Run: `cd apps/mobile; flutter test; flutter analyze`
Expected: all PASS, 0 issues.

---

### Task 8: Migration 0083 — convert legacy money to piastres

**Files:**
- Create: `supabase/migrations/0083_money_piastres_unification.sql`
- Test: `supabase/tests/0083_money_piastres_test.sql`

**Interfaces:**
- Produces: legacy slot-domain money stored in piastres: `service_slots.price`, `bookings.paid_amount`, `payments.amount`, `payment_proofs.amount_claimed` (all existing `int` columns — data multiplied by 100). RPC bodies that copy amount→paid_amount unchanged; RPCs and clients that *author* amounts switch to piastres semantics.

**Invariant:** after this migration, every money column in the database holds piastres. The event-booking domain already does (`*_piastres` columns, 0073+).

- [ ] **Step 1: Inventory the money path (read-only)**

Run these searches and record results in the report (they define Task 9's exact file list):

```bash
grep -rn "paid_amount\|\.amount\|amount_claimed\|price" apps/mobile/lib --include=*.dart | grep -v "_piastres\|Piastres"
grep -rn "paid_amount\|amount_claimed\|'price'\|\"price\"" apps/admin/lib --include=*.dart
grep -rln "price\|paid_amount\|amount" supabase/tests/*.sql
```

- [ ] **Step 2: Write the failing test**

Create `supabase/tests/0083_money_piastres_test.sql`. Seed a slot with price 50 (as the pre-migration EGP value would appear), replay, and assert the stored value is 5000:

```sql
begin;
select plan(3);

-- a slot priced 50 EGP before migration stores 5000 after
select is(
  (select price from public.service_slots
    where tenant_id = public.tenant_id()
    order by id limit 1),
  5000::int,
  'slot price is in piastres (5000 = 50 EGP)'
);

-- booking payment snapshot is piastres
-- (insert a booking + payment via book_slot/create_pending_payment like
--  0067_submit_payment_proof_test.sql does, with EGP-era amounts, then:)

-- payments.amount is piastres
select is(
  (select amount from public.payments order by id limit 1) >= 100,
  true,
  'payments.amount stored in piastres (>= 100 for any nonzero EGP amount)'
);

select is(
  (select amount_claimed from public.payment_proofs order by id limit 1) >= 100,
  true,
  'payment_proofs.amount_claimed stored in piastres'
);

select * from finish();
rollback;
```

Copy the booking/payment fixture setup from `supabase/tests/0067_submit_payment_proof_test.sql` (user creation, slot creation, RPC invocation) — use the same shapes; this suite runs after migration 0083 so any amounts you seed must be written as piastres (e.g. submit a proof with `p_amount => 5000`).

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/0083_money_piastres_unification.sql`:

```sql
-- 0083: unify legacy slot-domain money into integer piastres
-- (project invariant: 1 EGP = 100 piastres, all money integer piastres)
-- Event-booking domain (0073+) already stores piastres.

begin;

-- Data conversion (idempotency is NOT possible here: 0083 runs exactly once
-- per replay. Value 0 rows are safe under multiplication.)
update public.service_slots       set price          = price * 100;
update public.bookings            set paid_amount    = paid_amount * 100;
update public.payments            set amount         = amount * 100;
update public.payment_proofs      set amount_claimed = amount_claimed * 100;

commit;
```

RPC bodies need **no** SQL changes — audit them to confirm: `book_slot` snapshots `service_slots.price` into `bookings.paid_amount` (0028/0035/0048 — both sides now piastres, ratio preserved); `apply_payment` copies `payments.amount` → `bookings.paid_amount` (0071:261 — same); `create_pending_payment` passes the client-supplied amount through (0064/0063 — the client now sends piastres, see Task 9); `mark_cash_received` and `submit_payment_proof` validate `> 0` only (unchanged). If inventory in Step 1 reveals any RPC that *hardcodes* an EGP-denominated literal, multiply it by 100 and list it in the report.

- [ ] **Step 4: Update pgTAP fixtures**

Every suite that seeds an EGP-denominated money literal must have that literal ×100. Sweep these files (found in Step 1's grep; the known-affected list): `0007_available_slots_test.sql`, `0008_booking_state_machine_test.sql`, `0009_concurrency_test.sql`, `0012_apply_payment_test.sql`, `0015_manual_book_test.sql`, `0028_paid_amount_test.sql`, `0046_payment_refunded_test.sql`, `0066_manual_payment_foundations_test.sql`, `0067_submit_payment_proof_test.sql`, `0068_payment_decision_rpcs_test.sql`, `0069_mark_cash_received_test.sql`, `0071_review_fixes_test.sql`. Rule: any literal inserted into / compared against `price`, `paid_amount`, `payments.amount`, or `amount_claimed` is multiplied by 100 (e.g. `50` → `5000`); literals for event-booking `*_piastres` columns are already piastres — leave them. Also sweep `supabase/seed.sql` — seed slot prices are 0, so no change, but verify.

Run: `npx supabase db reset`, then run the **entire** `supabase/tests/` directory suite-by-suite with the docker-exec psql runner, grepping every output for `not ok`. **Every one of the 70+ suites must be clean.** (This is the gate for the whole plan — do not skip suites.)

---

### Task 9: Client money display/entry conversion (piastres at the seam)

**Files (from Task 8 Step 1 inventory — the known core list):**
- Modify: `apps/mobile/lib/features/booking/payment_proof_screen.dart` (displays `amount`, submits claimed amount)
- Modify: `apps/mobile/lib/features/booking/booking_detail_screen.dart:~200` (`_SummaryCard` — the known `dynamic price` finding)
- Modify: `apps/mobile/lib/features/booking/services_list_screen.dart` and any slot/price display in `apps/mobile/lib/features/booking/`
- Modify: `apps/mobile/lib/app_router.dart:14-36` (`paymentProofRoute` passes `amount` extra)
- Modify: `apps/admin/lib/features/payments/payments_admin_screen.dart:39` (`'${r['amount']} جنيه'`)
- Modify: admin cash sheets (`CashReceivedSheet`, `payment review queue` amount display) — locate via inventory grep

**Interfaces:**
- Produces: a tiny pure formatter in each app — no new package. In mobile `apps/mobile/lib/core/money_format.dart` and admin `apps/admin/lib/core/money_format.dart` (identical content):

```dart
/// All backend money is integer piastres (1 EGP = 100).
/// UI displays EGP; inputs collected in EGP are converted at the seam.
String formatEgp(int piastres) {
  final egp = piastres / 100.0;
  return '${egp.toStringAsFixed(egp.truncateToDouble() == egp ? 0 : 2)} ج.م';
}

int egpToPiastres(num egp) => (egp * 100).round();
```

- [ ] **Step 1: Write failing tests**

Mobile (`apps/mobile/test/core/money_format_test.dart`):

```dart
void main() {
  test('formats whole piastres without decimals', () {
    expect(formatEgp(5000), '50 ج.م');
  });
  test('formats fractional piastres with 2 decimals', () {
    expect(formatEgp(5050), '50.50 ج.م');
  });
  test('converts EGP entry to piastres', () {
    expect(egpToPiastres(50), 5000);
    expect(egpToPiastres(49.99), 4999);
  });
  test('zero stays zero', () {
    expect(formatEgp(0), '0 ج.م');
    expect(egpToPiastres(0), 0);
  });
}
```

Mirror in `apps/admin/test/core/money_format_test.dart`. Also update the payment-proof screen test to expect `formatEgp` output (e.g. amount 5000 displays `50 ج.م`) and to assert the submitted `p_amount` is piastres.

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/mobile; flutter test test/core/` — FAIL (file doesn't exist). Same for admin.

- [ ] **Step 3: Apply the seam conversion**

Rules (apply everywhere the inventory found a raw amount render or submit):
- **Display**: every `'${row['amount']}'`, `'$price'`, `'${r['price']} جنيه'`-style interpolation becomes `formatEgp((value as num).toInt())`. This simultaneously fixes the `_SummaryCard` `dynamic price` typing finding: type the field `final int pricePiastres;` and render `formatEgp(pricePiastres)`.
- **Entry**: any UI collecting an amount in EGP (payment proof claimed amount, `CashReceivedSheet`, payouts config where amounts are entered) converts before calling the repo: `egpToPiastres(entered)`. The repository layer stays piastres-transparent — no repo changes.
- **Router extra**: `paymentProofRoute` reads `amount` extra — it now receives piastres; pass through unchanged, and let `PaymentProofScreen` render with `formatEgp`.
- **payments_admin_screen.dart:39**: `Text('دفع #${r['id']} — ${formatEgp((r['amount'] as num).toInt())}')` (drop the hardcoded `جنيه` suffix — `formatEgp` includes `ج.م`).

- [ ] **Step 4: Full client gates**

Run: `cd apps/mobile; flutter test; flutter analyze` and `cd apps/admin; flutter test; flutter analyze`
Expected: all tests PASS, 0 analyzer issues on both. Any test that previously asserted EGP display must be updated to the piastres-based expectation — update assertions, not the formatter, to match the new contract.

---

## Final Verification (whole plan)

- [ ] `npx supabase db reset` replays 0001→0083 cleanly.
- [ ] Full pgTAP sweep: every file in `supabase/tests/` piped through `docker exec -i supabase_db_church psql -U postgres -d postgres`, output grepped for `not ok` / `Looks like you failed` — zero matches across all suites.
- [ ] `deno test --allow-env --allow-net supabase/functions/` — all PASS.
- [ ] `flutter analyze && flutter test` in both `apps/mobile` and `apps/admin` — 0 issues, all PASS.
- [ ] `git status` shows only files listed in this plan (plus new migrations/tests/brief artifacts).

## Self-Review Notes

- Spec coverage: all six verified CRITICAL/HIGH findings → Tasks 1–6; domain bifurcation → Task 7; money unification → Tasks 8–9. MEDIUM findings folded in: `apply_payment` search_path (Task 6), `audit_log.entity_id = 0` (Task 6), `dynamic price` typing (Task 9). Explicitly out of scope (LOW, follow-ups): dead admin auth screens, allocation-matrix decomposition, auth-widget duplication, diagnostic-engine dedup, English strings in analytics screens.
- The LOW/`export_report_button` repo-seam bypass was left out to keep the plan bounded — it can ride the same pattern as Tasks 3–4 later.
- Task ordering risk: Task 8 (data ×100) requires Task 9 (client seam) in the same commit, otherwise cash-entry screens write EGP into piastres columns — Part B must land atomically.
