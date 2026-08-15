# Security and Backend Hardening Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement verified security hardening fixes across CI workflows, edge functions (Paymob checkout & webhook), SQL tenant ID resolution precedence, admin router role gating, mobile video repository error handling, and async realtime cleanup.

**Architecture:** Enforce defense-in-depth across the platform: scope CI secrets to authenticated CLI steps; enforce Bearer authentication and malformed upstream JSON handling in `paymob-checkout`; reject non-positive order IDs and preserve PAID idempotency in `paymob-webhook`; prioritize DB tenant ID over JWT claims in `public.tenant_id()` in base migrations and migration `0038_security_hardening.sql`; restrict admin UI to explicit `ADMIN|PRIEST|SUPER_ADMIN` roles; join purchase relations in mobile video queries, unit-test all RPC parsing branches, and guard null payment IDs; make admin realtime unsubscribe async with `unawaited`.

**Tech Stack:** GitHub Actions, PostgreSQL 16 (Supabase SQL), Deno / TypeScript Edge Functions, Flutter (Dart, Riverpod, GoRouter, `qr_flutter`).

---

### Task 1: Tenant ID Precedence in Migrations & 0038 Hardening Migration

**Files:**
- Modify: `supabase/migrations/0001_init_schema.sql:233-243`
- Modify: `supabase/migrations/0002_rls_baseline.sql:3-13`
- Create: `supabase/migrations/0038_security_hardening.sql`
- Test: `supabase/tests/0002_rls_test.sql`

- [ ] **Step 1: Write the failing SQL test fixture**

Add test in `supabase/tests/0002_rls_test.sql` checking that user tenant ID in `public.users` overrides JWT tenant claim:

```sql
  -- Verify public.users.tenant_id takes precedence over JWT tenant claim
  set local role authenticated;
  set_config('request.jwt.claims',
             json_build_object('sub','11111111-1111-1111-1111-111111111111',
                               'role','authenticated',
                               'tenant_id','999'), true);
  perform tests.expect(public.tenant_id() = 1,
                       'public.tenant_id() must prioritize public.users.tenant_id over JWT claim');
  reset role;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker exec -i supabase_db_church psql -U postgres -d postgres -f supabase/tests/0002_rls_test.sql`
Expected: FAIL with `public.tenant_id() must prioritize public.users.tenant_id over JWT claim` (returned 999 instead of 1)

- [ ] **Step 3: Update `public.tenant_id()` in migrations and create `0038_security_hardening.sql`**

Update `supabase/migrations/0001_init_schema.sql` and `supabase/migrations/0002_rls_baseline.sql`:
```sql
create or replace function public.tenant_id()
returns bigint
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (select u.tenant_id::text from public.users u where u.id = auth.uid() and u.deleted_at is null),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'tenant_id',
    '1'
  )::bigint
$$;
```

Create `supabase/migrations/0038_security_hardening.sql`:
```sql
-- 0038: security hardening & tenant precedence migration for existing deployments
create or replace function public.tenant_id()
returns bigint
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (select u.tenant_id::text from public.users u where u.id = auth.uid() and u.deleted_at is null),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'tenant_id',
    '1'
  )::bigint
$$;

grant execute on function public.tenant_id() to anon, authenticated, service_role;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker exec -i supabase_db_church psql -U postgres -d postgres -f supabase/tests/0002_rls_test.sql`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0001_init_schema.sql supabase/migrations/0002_rls_baseline.sql supabase/migrations/0038_security_hardening.sql supabase/tests/0002_rls_test.sql
git commit -m "fix(db): prioritize public.users.tenant_id over JWT claims and add 0038 migration"
```

---

### Task 2: Paymob Webhook Positive Order ID Guard & PAID Idempotency

**Files:**
- Modify: `supabase/functions/paymob-webhook/index.ts:54-75`
- Test: `supabase/functions/paymob-webhook/index_test.ts`

- [ ] **Step 1: Write failing tests in `paymob-webhook/index_test.ts`**

Add tests for invalid merchant order IDs and duplicate `success: false` webhook on `PAID` payment:

```ts
Deno.test("paymob-webhook: non-positive or non-numeric merchant_order_id returns 400", async () => {
  const fake = new FakeClient(["payments"]);
  for (const badId of ["0", "-5", "abc", "12.34"]) {
    const badTxn = { ...TXN, order: { id: 501, merchant_order_id: badId } };
    const hmacPayload = buildHmacPayload(badTxn);
    const secret = "hmac_secret_123";
    const signature = await hmacSha512Hex(secret, hmacPayload);
    const req = new Request(`https://x/functions/v1/paymob-webhook?hmac=${signature}`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(badTxn),
    });
    const res = await handleRequest(req, {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      hmacKey: secret, applyPayment: async () => {}, applyVideoPayment: async () => {},
    });
    assertEquals(res.status, 400);
  }
});

Deno.test("paymob-webhook: failure webhook on already PAID payment returns already_processed without modifying status to FAILED", async () => {
  const fake = new FakeClient(["payments"]);
  fake.seed("payments", [{ id: 17, status: "PAID", merchant_order_id: "17" }]);
  const failedTxn = { ...TXN, success: false };
  const hmacPayload = buildHmacPayload(failedTxn);
  const secret = "hmac_secret_123";
  const signature = await hmacSha512Hex(secret, hmacPayload);
  const req = new Request(`https://x/functions/v1/paymob-webhook?hmac=${signature}`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(failedTxn),
  });
  const res = await handleRequest(req, {
    getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
    hmacKey: secret,
    applyPayment: async () => {},
    applyVideoPayment: async () => {},
  });
  assertEquals(res.status, 200);
  const body = await res.json() as Record<string, unknown>;
  assertEquals(body.already_processed, true);
  const pay = fake.tableRows("payments")[0];
  assertEquals(pay.status, "PAID");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test --allow-env --allow-net supabase/functions/paymob-webhook/index_test.ts`
Expected: FAIL on non-positive IDs or `pay.status` flipped to `FAILED`.

- [ ] **Step 3: Update `paymob-webhook/index.ts`**

Update lines 54-75 in `supabase/functions/paymob-webhook/index.ts`:

```ts
    const orderObj = (txn.order ?? {}) as Record<string, unknown>;
    const rawOrderId = orderObj.merchant_order_id;
    const numOrderId = Number(rawOrderId);
    if (
      rawOrderId == null ||
      rawOrderId === "" ||
      rawOrderId === "undefined" ||
      rawOrderId === "null" ||
      !Number.isInteger(numOrderId) ||
      numOrderId <= 0
    ) {
      return new Response(JSON.stringify({ error: "BAD_MERCHANT_ORDER_ID" }), { status: 400, headers: jsonHeaders });
    }
    const merchantOrderId = String(rawOrderId);
    const supabase = deps.getClient() as SupabaseClient;
    const paid = Boolean(txn.success);
    const { data: existing } = await supabase.from("payments")
      .select("id, gateway_ref, status, video_id").eq("merchant_order_id", merchantOrderId).maybeSingle();
    let pay: { id: number; status: string; video_id?: number | null };
    if (existing) {
      // Idempotency: if already processed as PAID, acknowledge without re-invoking state transitions or overwriting with FAILED
      if (existing.status === "PAID") {
        return new Response(JSON.stringify({ ok: true, already_processed: true }), { status: 200, headers: jsonHeaders });
      }
      const { data: updated, error: uErr } = await supabase.from("payments")
        .update({ gateway_ref: txn.id, raw_webhook: txn, ...(paid ? {} : { status: "FAILED" }) })
        .eq("id", existing.id).select().single();
      if (uErr) throw uErr;
      pay = updated as { id: number; status: string; video_id?: number | null };
    } else {
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test --allow-env --allow-net supabase/functions/paymob-webhook/`
Expected: PASS (all tests pass)

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/paymob-webhook/index.ts supabase/functions/paymob-webhook/index_test.ts
git commit -m "fix(paymob-webhook): enforce positive integer merchant_order_id and preserve PAID idempotency"
```

---

### Task 3: Paymob Checkout Bearer Token Enforcement & Malformed JSON 502 Handling

**Files:**
- Modify: `supabase/functions/paymob-checkout/index.ts:15-154`
- Test: `supabase/functions/paymob-checkout/index_test.ts`

- [ ] **Step 1: Write failing tests in `paymob-checkout/index_test.ts`**

Add tests for missing Authorization header and malformed JSON upstream responses from Paymob:

```ts
Deno.test("paymob-checkout: missing or invalid Authorization header returns 401", async () => {
  const fake = new FakeClient(["bookings", "payments"]);
  const res = await handleRequest(new Request("https://x/functions/v1/paymob-checkout", {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ booking_id: 7 }),
  }), {
    getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
    fetch: () => Promise.resolve(new Response("{}")), paymobApiKey: "sk", integrationId: 1, iframeId: 2, amountMultiplier: 100,
  });
  assertEquals(res.status, 401);
});

Deno.test("paymob-checkout: malformed upstream JSON marks created payment as FAILED and returns 502", async () => {
  const fake = new FakeClient(["bookings", "payments"]);
  fake.seed("bookings", [{ id: 7, user_id: "user-123", paid_amount: 50, status: "PENDING_PAYMENT" }]);
  const fetchStub = stub(globalThis, "fetch", () => Promise.resolve(new Response("<html>Bad Gateway</html>", { status: 200, headers: { "Content-Type": "text/html" } })));
  try {
    const res = await handleRequest(new Request("https://x/functions/v1/paymob-checkout", {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": "Bearer valid-token" },
      body: JSON.stringify({ booking_id: 7 }),
    }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      getUser: () => Promise.resolve({ data: { user: { id: "user-123" } as any }, error: null }),
      fetch: fetchStub, paymobApiKey: "sk", integrationId: 1, iframeId: 2, amountMultiplier: 100,
    });
    assertEquals(res.status, 502);
    const body = await res.json() as Record<string, unknown>;
    assertEquals(body.error, "PAYMOB_UPSTREAM_ERROR");
    const pay = fake.tableRows("payments")[0];
    assertEquals(pay.status, "FAILED");
  } finally { fetchStub.restore(); }
});
```

Update existing tests in `supabase/functions/paymob-checkout/index_test.ts` to include valid Authorization headers and `getUser` stubs.

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test --allow-env --allow-net supabase/functions/paymob-checkout/index_test.ts`
Expected: FAIL on missing token check or 500 received instead of 502 on malformed JSON.

- [ ] **Step 3: Update `paymob-checkout/index.ts`**

Update `supabase/functions/paymob-checkout/index.ts`:

```ts
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ") || !deps.getUser) {
      return new Response(JSON.stringify({ error: "UNAUTHORIZED" }), { status: 401, headers: cors });
    }
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!token) {
      return new Response(JSON.stringify({ error: "UNAUTHORIZED" }), { status: 401, headers: cors });
    }
    const { data, error: authErr } = await deps.getUser(token);
    if (authErr || !data?.user) {
      return new Response(JSON.stringify({ error: "UNAUTHORIZED" }), { status: 401, headers: cors });
    }
    const callerUser = data.user;
```

And wrap Paymob JSON decoding calls:
```ts
    // STEP 1: Auth token
    const authRes = await deps.fetch("https://accept.paymob.com/api/auth/tokens", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ api_key: deps.paymobApiKey }),
    });
    if (!authRes.ok) {
      if (createdPaymentId) await supabase.from("payments").update({ status: "FAILED" }).eq("id", createdPaymentId);
      return new Response(JSON.stringify({ error: "PAYMOB_UPSTREAM_ERROR" }), { status: 502, headers: cors });
    }
    let authJson: Record<string, unknown>;
    try {
      authJson = (await authRes.json()) as Record<string, unknown>;
    } catch {
      if (createdPaymentId) await supabase.from("payments").update({ status: "FAILED" }).eq("id", createdPaymentId);
      return new Response(JSON.stringify({ error: "PAYMOB_UPSTREAM_ERROR" }), { status: 502, headers: cors });
    }
    const token = String(authJson.token ?? "");
    if (!token) {
      if (createdPaymentId) await supabase.from("payments").update({ status: "FAILED" }).eq("id", createdPaymentId);
      return new Response(JSON.stringify({ error: "PAYMOB_UPSTREAM_ERROR" }), { status: 502, headers: cors });
    }

    // STEP 2: Order registration
    const orderRes = await deps.fetch("https://accept.paymob.com/api/ecommerce/orders", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        auth_token: token, delivery_needed: "false",
        amount_cents: String(amountCents), currency: "EGP",
        merchant_order_id: String(orderId), items: [],
      }),
    });
    if (!orderRes.ok) {
      if (createdPaymentId) await supabase.from("payments").update({ status: "FAILED" }).eq("id", createdPaymentId);
      return new Response(JSON.stringify({ error: "PAYMOB_UPSTREAM_ERROR" }), { status: 502, headers: cors });
    }
    let orderJson: Record<string, unknown>;
    try {
      orderJson = (await orderRes.json()) as Record<string, unknown>;
    } catch {
      if (createdPaymentId) await supabase.from("payments").update({ status: "FAILED" }).eq("id", createdPaymentId);
      return new Response(JSON.stringify({ error: "PAYMOB_UPSTREAM_ERROR" }), { status: 502, headers: cors });
    }
    const paymobOrderId = Number(orderJson.id ?? 0);
    if (!paymobOrderId) {
      if (createdPaymentId) await supabase.from("payments").update({ status: "FAILED" }).eq("id", createdPaymentId);
      return new Response(JSON.stringify({ error: "PAYMOB_UPSTREAM_ERROR" }), { status: 502, headers: cors });
    }

    // STEP 3: Payment key
    const keyRes = await deps.fetch("https://accept.paymob.com/api/acceptance/payment_keys", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        auth_token: token, amount_cents: String(amountCents),
        expiration: 3600, order_id: String(paymobOrderId),
        billing_data: { first_name: "Parishioner", last_name: "User", email: "p@example.com", phone_number: "+201000000000", country: "EG", city: "Cairo", street: "N/A", building: "N/A", floor: "N/A", apartment: "N/A" },
        currency: "EGP", integration_id: deps.integrationId,
      }),
    });
    if (!keyRes.ok) {
      if (createdPaymentId) await supabase.from("payments").update({ status: "FAILED" }).eq("id", createdPaymentId);
      return new Response(JSON.stringify({ error: "PAYMOB_UPSTREAM_ERROR" }), { status: 502, headers: cors });
    }
    let keyJson: Record<string, unknown>;
    try {
      keyJson = (await keyRes.json()) as Record<string, unknown>;
    } catch {
      if (createdPaymentId) await supabase.from("payments").update({ status: "FAILED" }).eq("id", createdPaymentId);
      return new Response(JSON.stringify({ error: "PAYMOB_UPSTREAM_ERROR" }), { status: 502, headers: cors });
    }
    const paymentKey = String(keyJson.token ?? "");
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test --allow-env --allow-net supabase/functions/paymob-checkout/`
Expected: PASS (all tests pass)

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/paymob-checkout/index.ts supabase/functions/paymob-checkout/index_test.ts
git commit -m "fix(paymob-checkout): enforce Bearer token authentication and catch malformed upstream JSON"
```

---

### Task 4: Reconcile Payments Deno.serve Isolation & CI Workflow Hardening

**Files:**
- Modify: `supabase/functions/reconcile-payments/index.ts:52`
- Modify: `.github/workflows/ci.yml:56-88`

- [ ] **Step 1: Write the failing check verification**

Run: `deno test --allow-env supabase/functions/reconcile-payments/index_test.ts`
Expected: FAIL without `--allow-net` because `Deno.serve` is eagerly executed when importing `reconcile-payments/index.ts`.

- [ ] **Step 2: Update `reconcile-payments/index.ts`**

Update line 52 in `supabase/functions/reconcile-payments/index.ts`:
```ts
if (import.meta.main && typeof Deno !== "undefined" && Deno.serve) {
```

- [ ] **Step 3: Update `.github/workflows/ci.yml`**

Update `deno-tests` job and `deploy-staging` job in `.github/workflows/ci.yml`:
```yaml
  deno-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: denoland/setup-deno@v2
        with:
          deno-version: v2.x
      - name: Check edge functions
        run: |
          if find supabase/functions -name '*.ts' -not -name '*_test.ts' | grep -q .; then
            deno check $(find supabase/functions -name '*.ts' -not -name '*_test.ts')
          fi
      - name: Run edge function test suite
        run: |
          deno test --allow-env --allow-net supabase/functions/

  deploy-staging:
    needs: [flutter-mobile, flutter-admin, sql-tests, deno-tests]
    if: github.ref == 'refs/heads/main'
    environment: staging
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v1
        with:
          version: latest
      - name: Supabase link
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
        run: supabase link --project-ref ${{ secrets.SUPABASE_PROJECT_REF }}
      - name: Push migrations
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
        run: supabase db push
      - name: Deploy edge functions
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
        run: |
          if find supabase/functions -name '*.ts' -not -name '*_test.ts' | grep -q .; then
            supabase functions deploy --project-ref ${{ secrets.SUPABASE_PROJECT_REF }}
          fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test --allow-env supabase/functions/reconcile-payments/index_test.ts`
Expected: PASS (passes cleanly without requiring `--allow-net` for test import)

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/reconcile-payments/index.ts .github/workflows/ci.yml
git commit -m "fix(ci): execute deno test in CI and scope SUPABASE_ACCESS_TOKEN to authenticated CLI steps"
```

---

### Task 5: Fail-Fast SUPABASE_ANON_KEY Validation & Documentation in Mobile & Admin

**Files:**
- Modify: `apps/mobile/lib/main.dart:21-31`
- Modify: `apps/admin/lib/main.dart:11-18`
- Modify: `apps/mobile/README.md:50-54`
- Modify: `apps/admin/README.md:40-45`
- Test: `apps/mobile/test/unit/main_env_test.dart`

- [ ] **Step 1: Write the unit test for environment validation**

Create `apps/mobile/test/unit/main_env_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';

void validateSupabaseAnonKey(String key) {
  if (key.isEmpty) {
    throw StateError(
      'Missing SUPABASE_ANON_KEY. Pass via --dart-define=SUPABASE_ANON_KEY=<key>',
    );
  }
}

void main() {
  test('validateSupabaseAnonKey throws StateError when empty', () {
    expect(() => validateSupabaseAnonKey(''), throwsA(isA<StateError>()));
  });

  test('validateSupabaseAnonKey passes when non-empty', () {
    expect(() => validateSupabaseAnonKey('valid-anon-key'), returnsNormally);
  });
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `flutter test apps/mobile/test/unit/main_env_test.dart`
Expected: PASS

- [ ] **Step 3: Update `apps/mobile/lib/main.dart`, `apps/admin/lib/main.dart`, and READMEs**

In `apps/mobile/lib/main.dart`:
```dart
const _supabasePublishableKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabasePublishableKey.isEmpty) {
    throw StateError(
      'Missing SUPABASE_ANON_KEY. Pass via --dart-define=SUPABASE_ANON_KEY=<key>',
    );
  }
  await Supabase.initialize(
    url: resolvedSupabaseUrl,
    publishableKey: _supabasePublishableKey,
  );
  runApp(const ProviderScope(child: ChurchApp()));
}
```

In `apps/admin/lib/main.dart`:
```dart
const _supabasePublishableKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabasePublishableKey.isEmpty) {
    throw StateError(
      'Missing SUPABASE_ANON_KEY. Pass via --dart-define=SUPABASE_ANON_KEY=<key>',
    );
  }
  await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabasePublishableKey);
  runApp(const ProviderScope(child: ChurchApp()));
}
```

In `apps/mobile/README.md` and `apps/admin/README.md`:
Document `--dart-define=SUPABASE_ANON_KEY=<anon-key> --dart-define=SUPABASE_URL=<url>`.

- [ ] **Step 4: Run flutter test suites**

Run: `flutter test apps/mobile/test/widget_test.dart && flutter test apps/admin/test/widget_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/main.dart apps/admin/lib/main.dart apps/mobile/README.md apps/admin/README.md apps/mobile/test/unit/main_env_test.dart
git commit -m "fix(core): fail fast on missing SUPABASE_ANON_KEY in mobile and admin entry points"
```

---

### Task 6: Admin Router Role Restriction & Fallback Fix

**Files:**
- Modify: `apps/admin/lib/app_router.dart:140-153`
- Test: `apps/admin/test/widget/router_guard_test.dart`

- [ ] **Step 1: Write failing router role tests in `router_guard_test.dart`**

Add test in `apps/admin/test/widget/router_guard_test.dart` verifying that `role == null` or non-admin role is redirected to `/login`:

```dart
  testWidgets('Authenticated user with null or unallowed role is redirected to /login', (tester) async {
    final router = createAdminRouter(
      isAuthenticated: () => true,
      getUserRole: () => null,
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.byType(AdminLoginScreen), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test apps/admin/test/widget/router_guard_test.dart`
Expected: FAIL (`role == null` was previously permitted)

- [ ] **Step 3: Update `createAdminRouter()` in `apps/admin/lib/app_router.dart`**

```dart
    redirect: (context, state) {
      final isAuthed = isAuthenticated != null
          ? isAuthenticated()
          : (resolveDb() is SupabaseClient
              ? (resolveDb() as SupabaseClient).auth.currentUser != null
              : false);
      final role = getUserRole != null ? getUserRole() : null;
      final hasAllowedRole = role != null && allowedAdminRoles.contains(role);
      final isAllowed = isAuthed && hasAllowedRole;
      final loggingIn = state.uri.path == '/login';
      if (!isAllowed) {
        return loggingIn ? null : '/login';
      }
      if (loggingIn) {
        return '/bookings';
      }
      return null;
    },
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test apps/admin/test/widget/router_guard_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add apps/admin/lib/app_router.dart apps/admin/test/widget/router_guard_test.dart
git commit -m "fix(admin): enforce non-null allowed role check in createAdminRouter and preserve auth fallback"
```

---

### Task 7: Videos Repository Parsing Safety, Unit Tests & Video Purchase Flow Safety

**Files:**
- Modify: `apps/mobile/lib/repositories/videos_repository.dart:12-40`
- Modify: `apps/mobile/lib/features/video/video_purchase_screen.dart:47-65`
- Create: `apps/mobile/test/unit/videos_repository_test.dart`
- Modify: `apps/mobile/test/features/video/video_purchase_screen_test.dart`

- [ ] **Step 1: Write failing tests in `apps/mobile/test/unit/videos_repository_test.dart` and `video_purchase_screen_test.dart`**

Create `apps/mobile/test/unit/videos_repository_test.dart` covering all response shapes (`num`, `String`, `Map`, unparsable `String`, `null`):
```dart
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic>? parsePurchaseRpcResult(dynamic data) {
  if (data == null) return null;
  if (data is num) return {'id': data.toInt()};
  if (data is String) {
    final parsed = int.tryParse(data);
    return parsed != null ? {'id': parsed} : null;
  }
  if (data is Map) {
    final id = data['id'];
    if (id != null) return Map<String, dynamic>.from(data);
    return null;
  }
  final parsed = int.tryParse(data.toString());
  return parsed != null ? {'id': parsed} : null;
}

void main() {
  test('parsePurchaseRpcResult handles num', () {
    expect(parsePurchaseRpcResult(42), equals({'id': 42}));
  });

  test('parsePurchaseRpcResult handles numeric string', () {
    expect(parsePurchaseRpcResult('123'), equals({'id': 123}));
  });

  test('parsePurchaseRpcResult handles map with valid id', () {
    expect(parsePurchaseRpcResult({'id': 50}), equals({'id': 50}));
  });

  test('parsePurchaseRpcResult returns null on unparsable input or invalid map', () {
    expect(parsePurchaseRpcResult('not-a-number'), isNull);
    expect(parsePurchaseRpcResult({'id': null}), isNull);
    expect(parsePurchaseRpcResult(null), isNull);
  });
}
```

And in `apps/mobile/test/features/video/video_purchase_screen_test.dart`:
```dart
  testWidgets(
    'purchased row with is_purchased or access_granted_at renders purchasedLabel and no buy button',
    (tester) async {
      final fake = FakeVideosRepository(
        videos: [
          {
            'id': 10,
            'title_ar': 'فيديو مميز',
            'price': 50,
            'event_date': '2024-12-26T00:00:00Z',
          },
          {
            'id': 11,
            'title_ar': 'فيديو مشتري 1',
            'price': 80,
            'event_date': '2024-12-25T00:00:00Z',
            'is_purchased': true,
          },
          {
            'id': 12,
            'title_ar': 'فيديو مشتري 2',
            'price': 60,
            'event_date': '2024-12-24T00:00:00Z',
            'access_granted_at': '2024-12-25T10:00:00Z',
          },
        ],
      );

      await tester.pumpWidget(
        MaterialApp(home: VideoPurchaseScreen(repository: fake)),
      );
      await tester.pumpAndSettle();

      expect(find.text('فيديو مشتري 1'), findsOneWidget);
      expect(find.text('فيديو مشتري 2'), findsOneWidget);
      expect(find.text(AppStrings.purchasedLabel), findsNWidgets(2));
    },
  );

  testWidgets('video purchase: null payment id shows error SnackBar and does not navigate', (
    tester,
  ) async {
    final fake = FakeVideosRepository(
      videos: [
        {
          'id': 1,
          'title_ar': 'قداس رئيسي',
          'price': 100,
          'event_date': '2024-12-26T00:00:00Z',
        },
        {
          'id': 5,
          'title_ar': 'عظة المولد',
          'price': 30,
          'event_date': '2024-12-25T00:00:00Z',
        },
      ],
      payment: null,
    );
    final fakeDb = TestAppSupabase({});
    await pumpWithRouter(
      tester,
      home: VideoPurchaseScreen(repository: fake),
      db: fakeDb,
    );
    final buyBtn = find.text(AppStrings.buyVideo);
    await tester.ensureVisible(buyBtn);
    await tester.tap(buyBtn);
    await tester.pumpAndSettle();
    expect(find.byType(PaymentRedirectScreen), findsNothing);
  });
```

- [ ] **Step 2: Run tests to verify failure**

Run: `flutter test apps/mobile/test/unit/videos_repository_test.dart apps/mobile/test/features/video/video_purchase_screen_test.dart`
Expected: PASS on unit test, FAIL on widget test (navigation check when payment is null).

- [ ] **Step 3: Update `videos_repository.dart` and `video_purchase_screen.dart`**

In `apps/mobile/lib/repositories/videos_repository.dart`:
```dart
  @override
  Future<List<Map<String, dynamic>>> fetchVideos() async {
    final res = await _client
        .from('videos')
        .select('id, title_ar, price, event_date, privacy, video_purchases(id, access_granted_at)')
        .order('event_date', ascending: false);
    return (res as List).map((r) {
      final map = Map<String, dynamic>.from(r as Map);
      final purchases = map['video_purchases'] as List?;
      final hasAccess = purchases != null &&
          purchases.isNotEmpty &&
          purchases.any((p) => p is Map && p['access_granted_at'] != null);
      map['is_purchased'] = hasAccess;
      return map;
    }).toList();
  }

  @override
  Future<Map<String, dynamic>?> purchaseVideo(int videoId) async {
    final data = await _client.rpc(
      'purchase_video',
      params: {'p_video_id': videoId},
    );
    if (data == null) return null;
    if (data is num) return {'id': data.toInt()};
    if (data is String) {
      final parsed = int.tryParse(data);
      return parsed != null ? {'id': parsed} : null;
    }
    if (data is Map) {
      final id = data['id'];
      if (id != null) return Map<String, dynamic>.from(data);
      return null;
    }
    final parsed = int.tryParse(data.toString());
    return parsed != null ? {'id': parsed} : null;
  }
```

In `apps/mobile/lib/features/video/video_purchase_screen.dart`:
```dart
  Future<void> _buy(int videoId) async {
    await PhoneVerifyGate.ensureAuth(
      context,
      gateway: resolveAuthGateway(widget.gateway),
      isLoggedIn: widget.isLoggedIn,
      onVerified: () async {
        await runGuarded(
          () async {
            final payment = await widget.repository.purchaseVideo(videoId);
            if (!mounted) return;
            final paymentId = payment?['id'];
            if (paymentId == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Failed to initiate payment')),
              );
              return;
            }
            context.pushNamed(
              AppRoutes.paymentRedirect,
              extra: {'video': true, 'payment_id': paymentId},
            );
          },
          onError: (message) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          },
        );
      },
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test apps/mobile/test/features/video/video_purchase_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/repositories/videos_repository.dart apps/mobile/lib/features/video/video_purchase_screen.dart apps/mobile/test/unit/videos_repository_test.dart apps/mobile/test/features/video/video_purchase_screen_test.dart
git commit -m "fix(mobile): validate non-null payment ID in video purchase flow, compute is_purchased and test RPC parsing"
```

---

### Task 8: Admin Bookings Realtime Unsubscribe Async Await

**Files:**
- Modify: `apps/admin/lib/features/bookings/bookings_provider.dart:1-100`
- Test: `apps/admin/test/features/bookings/bookings_admin_screen_test.dart`

- [ ] **Step 1: Write test verifying realtime subscription disposal**

In `apps/admin/test/features/bookings/bookings_admin_screen_test.dart`, verify channel unsubscribe is invoked cleanly on provider dispose.

- [ ] **Step 2: Run test to verify current state**

Run: `flutter test apps/admin/test/features/bookings/bookings_admin_screen_test.dart`
Expected: PASS

- [ ] **Step 3: Update `bookings_provider.dart`**

In `apps/admin/lib/features/bookings/bookings_provider.dart`:
```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
```

And update lifecycle disposal:
```dart
  @override
  BookingsState build() {
    final filter = ref.watch(bookingsFilterProvider);

    _subscribeRealtime();
    ref.onDispose(() {
      unawaited(_unsubscribeRealtime());
    });

    _loadBookings(filter);
    return BookingsState(isLoading: true, filter: filter);
  }
```

And update `_unsubscribeRealtime`:
```dart
  Future<void> _unsubscribeRealtime() async {
    if (_channel != null) {
      try {
        await _channel.unsubscribe();
      } catch (e, st) {
        debugPrint('Realtime unsubscribe error: $e\n$st');
      }
      _channel = null;
    }
  }
```

- [ ] **Step 4: Run admin tests to verify it passes**

Run: `flutter test apps/admin/test/features/bookings/bookings_admin_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add apps/admin/lib/features/bookings/bookings_provider.dart
git commit -m "fix(admin): make realtime unsubscribe async and unawaited on dispose"
```

---

### Task 9: Mobile QR Code Standards-Compliant Payload Verification Test

**Files:**
- Modify: `apps/mobile/test/features/booking/booking_ticket_screen_test.dart`

- [ ] **Step 1: Write payload decoding assertion test**

Update `apps/mobile/test/features/booking/booking_ticket_screen_test.dart`:
```dart
import 'package:qr_flutter/qr_flutter.dart';
```
And add widget inspection assertion in test 1:
```dart
      final qrFinder = find.byType(BookingQrView);
      expect(qrFinder, findsOneWidget);
      final qrImageViewFinder = find.byType(QrImageView);
      expect(qrImageViewFinder, findsOneWidget);
      final qrWidget = tester.widget<QrImageView>(qrImageViewFinder);
      expect(qrWidget.data, equals('CHURCH-TICKET-V1:123:قداس الأحد'));
      expect(qrWidget.errorCorrectionLevel, equals(QrErrorCorrectLevel.M));
```

- [ ] **Step 2: Run test to verify it passes**

Run: `flutter test apps/mobile/test/features/booking/booking_ticket_screen_test.dart`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/test/features/booking/booking_ticket_screen_test.dart
git commit -m "test(mobile): verify BookingQrView encodes full ticket payload with standard error correction"
```

---

### Task 10: Full Monorepo Regression Verification

**Files:**
- Test all suites: Deno functions, Flutter Mobile, Flutter Admin

- [ ] **Step 1: Run all Deno tests**

Run: `deno test --allow-env --allow-net supabase/functions/`
Expected: PASS (43+ tests passed)

- [ ] **Step 2: Run all Mobile tests**

Run: `flutter test apps/mobile/`
Expected: PASS (66+ tests passed)

- [ ] **Step 3: Run all Admin tests**

Run: `flutter test apps/admin/`
Expected: PASS (40+ tests passed)
