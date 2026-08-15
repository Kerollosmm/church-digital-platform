# Phase 0 — Foundations & Onboarding (Supabase) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Phase 0 (weeks 1–2): monorepo + CI, local Supabase stack, migrations 0001–0003 (full §5 schema, RLS baseline + audit trigger, RBAC seed), Flutter app scaffolds with working phone-OTP login screens, SQL regression tests, and the external-onboarding tracking table — so Phase 1 can start booking/payments on day 1.

**Architecture:** Supabase-first. PostgreSQL 16 owns all data via migrations 0001–0003; RLS is the security boundary (anon denied, authenticated read-own, ADMIN/SUPER_ADMIN full; complaints intentionally policy-free — Phase 1 owns its views). SECURITY DEFINER helpers `current_user_role()` (returns text) and `tenant_id()` (falls back to tenant 1 — single church, locked A7) back every policy. Two Flutter apps (mobile + web admin) talk directly to Supabase with go_router + Riverpod + supabase_flutter; phone-OTP auth via Supabase Auth (Twilio placeholder config). CI = flutter analyze/test ×2 + SQL tests + deno test + staging deploy on main.

**Tech Stack:** Supabase CLI (Docker local stack), PostgreSQL 16 (pg_cron, pg_net, supabase_vault), SQL (enums, RLS policies, triggers, psql DO-block tests), Flutter 3 (go_router, flutter_riverpod, supabase_flutter, flutter_localizations, intl), GitHub Actions, Deno 2 (`deno test`).

**Depends on:** Master blueprint `docs/superpowers/plans/2026-08-05-church-digital-platform.md` (§4 tech decisions, §5 data model, §7 external dependencies, §8 Phase 0, §9–13). No other plan.

> **Phase 0 owns migrations 0001–0003; Phase 1 uses 0004+.** Phase 1's tests run `supabase db reset` and expect 0001–0003 (schema, helpers, RLS, RBAC seed) plus `supabase/seed.sql` demo data (admin/parishioner users, services, priests, FAQ) to be present and green. Do not add migrations beyond 0003 in this plan.

**Assumptions (each verified against the Phase 1 plan — deviations from conventions are deliberate and flagged):**
1. `video_privacy` enum = `('PUBLIC','UNLISTED','PRIVATE')` — Phase 1's 0019 test inserts `'PUBLIC'` free videos; its own `create type` is guarded (`duplicate_object` → skip), so Phase 0's definition wins and must include PUBLIC.
2. `service_slots.status` is TEXT (`'OPEN'`/`'CLOSED'`); the `slot_status` values from conventions (AVAILABLE/BOOKED/CLOSED) are the *view* output computed by Phase 1's `v_available_slots`, not a column.
3. `bookings.created_by` is TEXT (`'system'`/`'employee'`), `waiting_list.status` TEXT (`'WAITING'` in Phase 0; Phase 1 adds `'OFFERED'`), `whatsapp_outbox.status`/`whatsapp_optins.source` TEXT (Phase 1 0014 adds the CHECK constraints). No enums for these.
4. `tenant_id()` coalesces to `1` when `auth.uid()` is null — Phase 1's cron jobs and tests call `public.tenant_id()` as `postgres` (its 0007 test seeds a booking with it) and its anon-read policies (`tenant_id = public.tenant_id()`) require a non-null result for anon.
5. `whatsapp_outbox.tenant_id` / `whatsapp_optins.tenant_id` are NULLABLE with no default — Phase 1 inserts these tables from service-role/postgres contexts without tenant_id; a NOT NULL default would break Phase 1.
6. `audit_log.entity_id` is `bigint` — Phase 1 writes booking/payment ids into it.
7. `payments.booking_id` is NOT NULL (Phase 1 0019 drops the NOT NULL); no unique on `gateway_ref` (Phase 1 0012 creates `uq_payments_gateway_ref`); the constraint `bookings_status_check` exists with the exact values Phase 1 0008 drops+re-adds.
8. `current_user_role()` returns TEXT (Phase 1 assigns it to a `text` variable); `complaints` has NO baseline policies (Phase 1 0005 adds deny-all + views; `body_encrypted` must never be readable via PostgREST).
9. `supabase/seed.sql` guards its `faq` inserts with `to_regclass` (faq table is created in Phase 1 0004) so `supabase db reset` works during Phase 0 AND Phase 1.
10. A `handle_new_user` trigger (auth.users → public.users) lives in 0002 — Phase 1's `book_slot` FKs `auth.uid()` to `public.users`, so real OTP sign-ups need auto-created profiles.

**Local DB URL used in all psql commands:** `postgresql://postgres:postgres@127.0.0.1:54322/postgres` (supabase CLI local default).

---

### Task A: External onboarding checklist (tracking table)

**Files:**
- Create: `docs/external-onboarding-checklist.md`

Not unit-testable (process doc). Step 1 creates it; step 2 commits; the weekly ritual is documented inside the file.

- [ ] **Step 1: Write the tracking table**

Create `docs/external-onboarding-checklist.md`:

```markdown
# External Onboarding Checklist (master plan §7 — START NOW, runs parallel to all coding)

Weekly review ritual (every Sunday, 15 min, dev standup): update Status per row;
escalate anything older than its lead time to the church liaison owner.

| # | Dependency | Action needed | Lead time | Owner | Status (date) |
|---|-----------|---------------|-----------|-------|---------------|
| 1 | Paymob merchant account (under church charity association) | KYC documents, bank account, onboarding | 1-4 weeks | Church admin + dev | NOT_STARTED |
| 2 | Meta Business Manager + WhatsApp Business Account | Business verification, phone, test number | 2-7 days | Dev | NOT_STARTED |
| 3 | WhatsApp template submissions | booking_confirmed, payment_received ({{1}}=link), cancelled, rescheduled, apology, otp (+ Phase 1: booking_payment_received, booking_offer) | 3-14 days/round | Dev | NOT_STARTED |
| 4 | YouTube channel phone verification | One-time; needed for >15 min uploads | minutes-hours | Media team | NOT_STARTED |
| 5 | Google Play Console ($25) | Account setup | 1-5 days | Dev | NOT_STARTED |
| 6 | Supabase project | Sign up, org + project, region Frankfurt | 1 day | Dev | NOT_STARTED |
| 7 | SMS provider for OTP | Twilio trial/paid or Egyptian aggregator (webhook custom provider) | 1-3 days | Dev | NOT_STARTED |
| 8 | Domain + DNS | e.g. church-name-eg.org | 1 day | Church admin | NOT_STARTED |

Status values: NOT_STARTED / IN_PROGRESS / DONE / BLOCKED (note why + who unblocks).

Open questions to resolve alongside (master §16): (1) which charity association entity
holds the Paymob account; (2) which church committee member owns onboarding follow-ups;
(4) Twilio vs local SMS aggregator — test on Vodafone/Etisalat/Orange.
```

- [ ] **Step 2: Commit**

```bash
git add docs/external-onboarding-checklist.md
git commit -m "docs: external onboarding checklist tracking table (master §7)"
```

---

### Task B: Monorepo scaffold

**Files:**
- Create: `.gitignore`
- Create: `README.md`
- Create: `.github/workflows/.gitkeep` (placeholder until Task J)

- [ ] **Step 1: git init + layout**

Run: `git init`
Expected: `Initialized empty Git repository in C:/church/.git`

Run: `New-Item -ItemType Directory -Force -Path .github\workflows, apps, supabase, supabase\tests, supabase\functions\_tests | Out-Null`
Expected: no output (dirs created; `docs` already exists with the plans).

- [ ] **Step 2: Write root .gitignore**

Create `.gitignore`:

```gitignore
# Dart / Flutter
.dart_tool/
build/
.flutter-plugins
.flutter-plugins-dependencies
.packages
*.iml

# Supabase CLI local artifacts
supabase/.temp/
supabase/.branches
supabase/.env
.branches
.temp/

# Secrets — never commit
.env
*.env
!*.env.example

# IDE / OS
.idea/
.vscode/
Thumbs.db
.DS_Store
```

- [ ] **Step 3: Write README.md**

Create `README.md`:

```markdown
# Church Digital Platform

Single Egyptian Coptic church: parishioner app + admin dashboard + booking/payment engine
(Paymob) + WhatsApp automation + paid video access + analytics.

Stack: Flutter (mobile + web admin) · Supabase (PostgreSQL 16, Auth phone OTP, RLS, Edge
Functions) · Paymob · WhatsApp Cloud API · YouTube unlisted videos.

Layout:
- `apps/mobile` — Flutter app (parishioners, Android/iOS)
- `apps/admin` — Flutter Web PWA (employees, priests, super admins)
- `supabase/migrations` — ordered SQL migrations (Phase 0 owns 0001–0003; Phase 1 uses 0004+)
- `supabase/tests` — psql DO-block regression tests
- `supabase/functions` — Deno Edge Functions
- `supabase/seed.sql` — demo data (users, services, priests, FAQ)
- `.github/workflows` — CI (flutter analyze/test, SQL tests, deno test, staging deploy)
- `docs/superpowers/plans` — plan documents (master blueprint + per-phase plans)

Local dev: `supabase start` (Docker), `supabase db reset`, then
`psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/run_all.sql`.
Full conventions: `docs/superpowers/plans/conventions.md`.
```

- [ ] **Step 4: First commit**

```bash
git add -A
git commit -m "chore: initial monorepo scaffold (gitignore, readme, layout)"
```

- [ ] **Step 5: Create GitHub repo**

Run: `gh repo create church-platform --private --source=. --push`
Expected: `✓ Created repository <owner>/church-platform on GitHub` (requires `gh auth login` first if not authenticated).

---

### Task C: Flutter apps scaffold (mobile + admin) with smoke tests

**Files:**
- Create: `apps/mobile` (flutter create), `apps/admin` (flutter create)
- Create: `apps/mobile/lib/main.dart`, `apps/mobile/lib/app_router.dart`, `apps/mobile/lib/screens/home_screen.dart`
- Create: `apps/admin/lib/main.dart`, `apps/admin/lib/app_router.dart`, `apps/admin/lib/screens/home_screen.dart`
- Test: `apps/mobile/test/widget_test.dart`, `apps/admin/test/widget_test.dart`

- [ ] **Step 1: Create both projects + dependencies**

```bash
flutter create --org eg.church --project-name mobile --platforms android,ios apps/mobile
flutter create --org eg.church --project-name admin --platforms web apps/admin
```

```bash
flutter pub add go_router flutter_riverpod supabase_flutter
flutter pub add flutter_localizations --sdk=flutter
```

Run the two `flutter pub add` blocks once with `workdir = apps/mobile`, then again with `workdir = apps/admin`.
Expected: `+ go_router ...`, `+ flutter_riverpod ...`, `+ supabase_flutter ...`, `+ flutter_localizations ...` printed for each app.

- [ ] **Step 2: Write the failing smoke test (mobile)**

Overwrite `apps/mobile/test/widget_test.dart` (replace flutter create's template test):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile/screens/home_screen.dart';

void main() {
  testWidgets('home smoke renders with mocked supabase client', (tester) async {
    final supabase = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
    await tester.pumpWidget(MaterialApp(home: HomeScreen(supabase: supabase)));
    expect(find.text('مرحباً بكم في الكنيسة'), findsOneWidget);
    expect(find.text('غير مسجل'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run it, expect FAIL**

Run (workdir `apps/mobile`): `flutter test`
Expected: FAIL — `Target of URI doesn't exist: 'package:mobile/screens/home_screen.dart'`.

- [ ] **Step 4: Implement mobile app (main, router, home)**

Create `apps/mobile/lib/screens/home_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.supabase});

  final SupabaseClient supabase;

  @override
  Widget build(BuildContext context) {
    final phone = supabase.auth.currentUser?.phone;
    return Scaffold(
      appBar: AppBar(title: const Text('الكنيسة')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('مرحباً بكم في الكنيسة', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            Text(phone == null ? 'غير مسجل' : 'مسجل: $phone'),
          ],
        ),
      ),
    );
  }
}
```

Create `apps/mobile/lib/app_router.dart`:

```dart
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/home_screen.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (_, __) => HomeScreen(supabase: Supabase.instance.client),
    ),
  ],
);
```

Overwrite `apps/mobile/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_router.dart';

const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://127.0.0.1:54321',
);
const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  runApp(const ProviderScope(child: ChurchApp()));
}

class ChurchApp extends StatelessWidget {
  const ChurchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: appRouter,
      title: 'كنيسة',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(useMaterial3: true),
    );
  }
}
```

- [ ] **Step 5: Run it, expect PASS**

Run (workdir `apps/mobile`): `flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: Admin app — same TDD loop (full code)**

Overwrite `apps/admin/test/widget_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin/screens/home_screen.dart';

void main() {
  testWidgets('home smoke renders with mocked supabase client', (tester) async {
    final supabase = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
    await tester.pumpWidget(MaterialApp(home: HomeScreen(supabase: supabase)));
    expect(find.text('لوحة إدارة الكنيسة'), findsOneWidget);
    expect(find.text('غير مسجل'), findsOneWidget);
  });
}
```

Run (workdir `apps/admin`): `flutter test` — Expected: FAIL — `Target of URI doesn't exist: 'package:admin/screens/home_screen.dart'`.

Create `apps/admin/lib/screens/home_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.supabase});

  final SupabaseClient supabase;

  @override
  Widget build(BuildContext context) {
    final phone = supabase.auth.currentUser?.phone;
    return Scaffold(
      appBar: AppBar(title: const Text('لوحة الإدارة')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('لوحة إدارة الكنيسة', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            Text(phone == null ? 'غير مسجل' : 'مسجل: $phone'),
          ],
        ),
      ),
    );
  }
}
```

Create `apps/admin/lib/app_router.dart`:

```dart
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/home_screen.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (_, __) => HomeScreen(supabase: Supabase.instance.client),
    ),
  ],
);
```

Overwrite `apps/admin/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_router.dart';

const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://127.0.0.1:54321',
);
const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  runApp(const ProviderScope(child: ChurchApp()));
}

class ChurchApp extends StatelessWidget {
  const ChurchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: appRouter,
      title: 'لوحة الإدارة',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(useMaterial3: true),
    );
  }
}
```

Run (workdir `apps/admin`): `flutter test`
Expected: `All tests passed!`

- [ ] **Step 7: Commit**

```bash
git add apps/mobile apps/admin
git commit -m "feat(apps): scaffold mobile + admin flutter apps (go_router, riverpod, supabase_flutter, arabic RTL)"
```

---

### Task D: Supabase CLI local stack

**Files:**
- Create: `supabase/config.toml` (generated by `supabase init`)
- Test: `supabase/tests/0000_health_test.sql`

Requires Docker Desktop running (start it first if needed).

- [ ] **Step 1: Init supabase project**

Run: `supabase init`
Expected: `Finished supabase init.` and `supabase/config.toml` created (contains generated secrets; keep them local).

- [ ] **Step 2: Write the failing health test**

Create `supabase/tests/0000_health_test.sql`:

```sql
\set ON_ERROR_STOP on
do $$
begin
  if current_database() <> 'postgres' then
    raise exception 'FAIL: expected database postgres, got %', current_database();
  end if;
  if not exists (select 1 from pg_namespace where nspname = 'auth') then
    raise exception 'FAIL: auth schema missing (Supabase Auth not running)';
  end if;
  if not exists (select 1 from pg_tables where schemaname = 'auth' and tablename = 'users') then
    raise exception 'FAIL: auth.users table missing';
  end if;
end $$;
```

- [ ] **Step 3: Run it, expect FAIL**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0000_health_test.sql`
Expected: FAIL — `could not connect to server: Connection refused` (stack not started yet).

- [ ] **Step 4: Start the local stack**

Run: `supabase start`
Expected (first run takes several minutes — Docker pulls images; later runs are seconds): a table of services with URLs — `API URL: http://127.0.0.1:54321`, `DB URL: postgresql://postgres:postgres@127.0.0.1:54322/postgres`, `Studio URL`, plus the local anon key (matches the app default in Task C).

- [ ] **Step 5: Run it, expect PASS**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0000_health_test.sql`
Expected: no output, exit code 0.

Also run: `supabase status`
Expected: `Local project is running` with API/DB/Studio URLs.

- [ ] **Step 6: Commit**

```bash
git add supabase/config.toml supabase/tests/0000_health_test.sql
git commit -m "chore(supabase): local stack config + health test (supabase start)"
```

---

### Task E: Migration 0001 — full schema (enums, 15 tables, lock index, extensions)

**Files:**
- Create: `supabase/migrations/0001_init_schema.sql`
- Test: `supabase/tests/0001_schema_test.sql`

- [ ] **Step 1: Write the failing schema test**

Create `supabase/tests/0001_schema_test.sql`:

```sql
\set ON_ERROR_STOP on
create schema if not exists tests;
create or replace function tests.expect(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if not p_cond then raise exception 'FAIL: %', p_msg; end if;
end $$;

do $$
declare t text;
begin
  foreach t in array array['users','roles_permissions','priests','services','service_slots',
                          'bookings','payments','waiting_list','videos','video_purchases',
                          'complaints','announcements','audit_log','whatsapp_outbox','whatsapp_optins'] loop
    perform tests.expect(
      exists (select 1 from pg_tables where schemaname = 'public' and tablename = t),
      'table missing: ' || t);
  end loop;
end $$;

do $$
declare e text; v_count int;
begin
  foreach e in array array['app_role','booking_status','payment_status','video_privacy',
                          'complaint_status'] loop
    perform tests.expect(
      exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
              where n.nspname = 'public' and t.typname = e and t.typtype = 'e'),
      'enum missing: ' || e);
  end loop;
  select count(*) into v_count from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'app_role';
  perform tests.expect(v_count = 4, 'app_role must have 4 values (PARISHIONER, PRIEST, ADMIN, SUPER_ADMIN)');
  select count(*) into v_count from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'booking_status';
  perform tests.expect(v_count = 6, 'booking_status must have 6 values');
  select count(*) into v_count from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'video_privacy';
  perform tests.expect(v_count = 3, 'video_privacy must have 3 values (PUBLIC, UNLISTED, PRIVATE)');
end $$;

do $$
declare e text;
begin
  foreach e in array array['pg_cron','pg_net','supabase_vault'] loop
    perform tests.expect(exists (select 1 from pg_extension where extname = e),
      'extension missing: ' || e);
  end loop;
  -- the slot lock lives in book_slot() (FOR UPDATE + capacity count); assert that the
  -- buggy capacity-killing unique index does NOT exist
  perform tests.expect(not exists (select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'uq_active_booking_per_slot'),
    'lock index uq_active_booking_per_slot must NOT exist (breaks multi-seat slots)');
  -- sanity: bookings has the columns book_slot relies on
  perform tests.expect(exists (select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'bookings' and column_name = 'locked_until'),
    'bookings.locked_until missing');
  perform tests.expect(exists (select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'service_slots' and column_name = 'capacity'),
    'service_slots.capacity missing');
end $$;
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0001_schema_test.sql`
Expected: FAIL — `FAIL: table missing: users` (DB is still the empty base stack from Task D). NOTE: do NOT run `supabase db reset` yet — `supabase/seed.sql` (Task H) requires 0001 to exist.

- [ ] **Step 3: Write migration 0001**

Create `supabase/migrations/0001_init_schema.sql`:

```sql
-- 0001: full schema per master plan §5 + conventions. Phase 0 owns 0001-0003.
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

create type public.app_role as enum ('PARISHIONER','PRIEST','ADMIN','SUPER_ADMIN');
create type public.booking_status as enum ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED','COMPLETED','CANCELLED','RESCHEDULED');
create type public.payment_status as enum ('CREATED','PAID','FAILED','REFUNDED','REFUND_PENDING','PENDING');
create type public.video_privacy as enum ('PUBLIC','UNLISTED','PRIVATE');
create type public.complaint_status as enum ('NEW','ASSIGNED','RESOLVED');

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  phone text not null unique,
  name text not null default '',
  role public.app_role not null default 'PARISHIONER',
  fcm_token text,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.roles_permissions (
  id bigint generated always as identity primary key,
  role public.app_role not null,
  resource text not null,
  action text not null check (action in ('READ','CREATE','UPDATE','DELETE')),
  unique (role, resource, action)
);

create table public.priests (
  id bigint generated always as identity primary key,
  name text not null,
  photo_url text,
  bio text,
  visitation_hours jsonb not null default '{}'::jsonb,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.services (
  id bigint generated always as identity primary key,
  title_ar text not null,
  description text,
  schedule jsonb not null default '{}'::jsonb,
  location text,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.service_slots (
  id bigint generated always as identity primary key,
  service_id bigint not null references public.services(id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  capacity int not null default 0,
  price int not null default 0,
  status text not null default 'OPEN',
  location text,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.bookings (
  id bigint generated always as identity primary key,
  slot_id bigint not null references public.service_slots(id),
  user_id uuid not null references public.users(id),
  status public.booking_status not null default 'PENDING_PAYMENT',
  paid_amount int not null default 0,
  payment_ref text,
  locked_until timestamptz,
  created_by text not null default 'system',
  notes text,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint bookings_status_check check (status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED','COMPLETED','CANCELLED','RESCHEDULED')),
  constraint bookings_locked_until_check check (locked_until is null or status = 'PENDING_PAYMENT'),
  constraint bookings_paid_amount_check check (paid_amount >= 0)
);

create table public.payments (
  id bigint generated always as identity primary key,
  booking_id bigint not null references public.bookings(id),
  gateway_ref text,
  amount int not null default 0,
  status public.payment_status not null default 'CREATED',
  raw_webhook jsonb,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.waiting_list (
  id bigint generated always as identity primary key,
  slot_id bigint not null references public.service_slots(id),
  user_id uuid not null references public.users(id),
  position int not null,
  status text not null default 'WAITING',
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.videos (
  id bigint generated always as identity primary key,
  title_ar text not null,
  event_date timestamptz not null,
  yt_url text not null,
  price int not null check (price >= 0),
  privacy public.video_privacy not null default 'UNLISTED',
  expires_after_days int,
  uploaded_by uuid,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.video_purchases (
  id bigint generated always as identity primary key,
  video_id bigint not null references public.videos(id),
  user_id uuid not null references public.users(id),
  payment_id bigint not null references public.payments(id),
  access_granted_at timestamptz,
  link_sent_at timestamptz,
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.complaints (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.users(id),
  category text not null,
  body_encrypted bytea not null,
  status public.complaint_status not null default 'NEW',
  assigned_to uuid references public.users(id),
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.announcements (
  id bigint generated always as identity primary key,
  title_ar text not null,
  body_ar text not null,
  target_role public.app_role,
  published_at timestamptz not null default now(),
  tenant_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  user_id uuid,
  action text not null,
  entity_type text not null,
  entity_id bigint,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.whatsapp_outbox (
  id bigint generated always as identity primary key,
  phone text not null,
  template_name text not null,
  params jsonb not null default '{}'::jsonb,
  status text not null default 'PENDING',
  attempts int not null default 0,
  next_attempt_at timestamptz not null default now(),
  tenant_id bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.whatsapp_optins (
  phone text primary key,
  consented_at timestamptz not null default now(),
  source text not null default 'BOOKING',
  tenant_id bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- the slot lock (A8, conventions): FOR UPDATE row lock + capacity count inside
-- book_slot() — NO unique partial index (it would cap every slot at 1 booking)
```

- [ ] **Step 4: Apply + run test, expect PASS**

Run: `supabase db reset; psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0001_schema_test.sql`
Expected: `supabase db reset` exits 0 (applies 0001); psql prints no output, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0001_init_schema.sql supabase/tests/0001_schema_test.sql
git commit -m "feat(db): 0001 full schema (enums, 15 tables, extensions)"
```

---

### Task F: Migration 0002 — RLS baseline, helpers, audit trigger

**Files:**
- Create: `supabase/migrations/0002_rls_baseline.sql`
- Test: `supabase/tests/0002_rls_test.sql`

**Goal:** Lock the schema behind row-level security and provide the shared helpers that Phase 1 (book_slot, cron jobs, policies in 0004–0020) depends on: `tenant_id()`, `current_user_role()`, the `audit_trigger()`, and the `handle_new_user` trigger (auth.users → public.users; Phase 1's `book_slot` FKs `auth.uid()` to `public.users`).

**Architecture:** SQL migration + psql DO-block tests. Helpers are `SECURITY DEFINER` with `set search_path = ''` (Phase 1 calls them from cron as postgres, from policies as anon, and from `v_*` views). RLS is enabled on all 15 tables; one `p0_admin_all` policy per table on the 13 non-sensitive tables — **never** on `complaints` (Phase 1 0005 owns deny-all + views; `body_encrypted` bytea must stay invisible to PostgREST). Policy names are prefixed `p0_` so Phase 1's own policy names cannot collide. `tenant_id()` coalesces to 1 when no JWT claims exist (anon/postgres/cron contexts) — required by Phase 1 cron jobs. `whatsapp_outbox`/`whatsapp_optins` get **no** tenant default (their `tenant_id` stays NULLable, per Phase 1 0014 inserts from service-role contexts).

**Tech Stack:** PostgreSQL 16 (supabase local), plpgsql.

**Depends on:** Task E (0001 applied; runs after every `supabase db reset`).

- [ ] **Step 1: Write the failing RLS test**

Create `supabase/tests/0002_rls_test.sql`:

```sql
\set ON_ERROR_STOP on
create schema if not exists tests;
create or replace function tests.expect(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if not p_cond then raise exception 'FAIL: %', p_msg; end if;
end $$;

begin;
  insert into auth.users (id, instance_id, aud, role, email, phone,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'p0-parishioner@test.local', '+201000000099',
          '{}', '{"name":"P0 Parishioner"}', now(), now()),
         ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'p0-admin@test.local', '+201000000098',
          '{}', '{"name":"P0 Admin"}', now(), now());
  update public.users set role = 'ADMIN' where id = '22222222-2222-2222-2222-222222222222';
  insert into public.services (title_ar, tenant_id) values ('قداس اختبار', 1);
  insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, tenant_id)
    values (1, now() + interval '1 day', now() + interval '1 day' + interval '1 hour', 10, 0, 1);
  insert into public.bookings (slot_id, user_id, tenant_id) values (1, '11111111-1111-1111-1111-111111111111', 1);

  perform tests.expect(
    exists (select 1 from public.users where id = '11111111-1111-1111-1111-111111111111'),
    'handle_new_user did not create public.users row');
  perform tests.expect(
    exists (select 1 from public.audit_log where entity_type = 'bookings'),
    'audit_trigger did not write audit_log row');
  perform tests.expect(
    (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = 'complaints') = 0,
    'complaints must have NO baseline policies (Phase 1 owns them)');
  perform tests.expect(
    (select count(*) from pg_tables t
     where t.schemaname = 'public'
       and t.tablename in ('users','roles_permissions','priests','services','service_slots',
                           'bookings','payments','waiting_list','videos','video_purchases',
                           'complaints','announcements','audit_log','whatsapp_outbox','whatsapp_optins')
       and t.rowsecurity) = 15,
    'RLS must be enabled on all 15 tables');

  set local role anon;
  set_config('request.jwt.claims',
             '{"sub":"00000000-0000-0000-0000-000000000000","role":"anon"}', true);
  perform tests.expect((select count(*) from public.bookings) = 0,
                       'anon must see 0 bookings');
  begin
    insert into public.bookings (slot_id, user_id, tenant_id)
      values (1, '11111111-1111-1111-1111-111111111111', 1);
    perform tests.expect(false, 'anon INSERT into bookings must be denied by RLS');
  exception when others then
    perform tests.expect(true, 'anon INSERT denied as expected');
  end;
  reset role;

  set local role authenticated;
  set_config('request.jwt.claims',
             json_build_object('sub','11111111-1111-1111-1111-111111111111',
                               'role','authenticated'), true);
  perform tests.expect((select count(*) from public.bookings) = 1,
                       'parishioner must see exactly own booking');
  perform tests.expect((select count(*) from public.users) = 1,
                       'parishioner must see only own profile row');
  reset role;

  set local role authenticated;
  set_config('request.jwt.claims',
             json_build_object('sub','22222222-2222-2222-2222-222222222222',
                               'role','authenticated'), true);
  perform tests.expect((select count(*) from public.users) = 2,
                       'admin must see all users');
  perform tests.expect((select count(*) from public.bookings) = 1,
                       'admin must see all bookings');
  reset role;
rollback;
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0002_rls_test.sql`
Expected: FAIL — `handle_new_user did not create public.users row` (trigger, helpers, and policies do not exist yet). No reset needed; RLS is off so the inserts succeed and the audit/profile assertions fail first.

- [ ] **Step 3: Write migration 0002**

Create `supabase/migrations/0002_rls_baseline.sql`:

```sql
-- 0002: helpers + RLS baseline + audit + auto-provisioning. Phase 0 owns 0001-0003.

create or replace function public.tenant_id()
returns bigint
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'tenant_id',
    '1'
  )::bigint
$$;

create or replace function public.current_user_role()
returns text
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (select u.role::text from public.users u
     where u.id = auth.uid() and u.deleted_at is null),
    'anon'
  )
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'users','roles_permissions','priests','services','service_slots','bookings','payments',
    'waiting_list','videos','video_purchases','complaints','announcements','audit_log',
    'whatsapp_outbox','whatsapp_optins']
  loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'users','priests','services','service_slots','bookings','payments','waiting_list',
    'videos','video_purchases','complaints','announcements']
  loop
    execute format('alter table public.%I alter column tenant_id set default public.tenant_id()', t);
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'users','roles_permissions','priests','services','service_slots','bookings','payments',
    'waiting_list','videos','video_purchases','announcements','audit_log','whatsapp_outbox',
    'whatsapp_optins']
  loop
    execute format($f$
      create policy p0_admin_all on public.%I
      for all to authenticated
      using (public.current_user_role() in ('ADMIN','SUPER_ADMIN'))
      with check (public.current_user_role() in ('ADMIN','SUPER_ADMIN'))
    $f$, t);
  end loop;
end $$;

create policy p0_users_read_own on public.users
  for select to authenticated
  using (id = auth.uid());

create policy p0_bookings_read_own on public.bookings
  for select to authenticated
  using (user_id = auth.uid());

create or replace function public.audit_trigger()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (
    auth.uid(),
    tg_op,
    tg_table_name,
    case when tg_op = 'DELETE' then old.id else new.id end,
    jsonb_build_object(
      'old', case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
      'new', case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end
    )
  );
  return case when tg_op = 'DELETE' then old else new end;
end $$;

create trigger trg_bookings_audit after insert or update or delete on public.bookings
  for each row execute function public.audit_trigger();
create trigger trg_payments_audit after insert or update or delete on public.payments
  for each row execute function public.audit_trigger();
create trigger trg_complaints_audit after insert or update or delete on public.complaints
  for each row execute function public.audit_trigger();

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.users (id, phone, name, tenant_id)
  values (new.id, coalesce(new.phone, ''), coalesce(new.raw_user_meta_data ->> 'name', ''), 1)
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
```

- [ ] **Step 4: Apply + run test, expect PASS**

Run: `supabase db reset; psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0002_rls_test.sql`
Expected: `supabase db reset` exits 0 (applies 0001 + 0002; no `seed.sql` yet, so nothing to seed); psql prints no output, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0002_rls_baseline.sql supabase/tests/0002_rls_test.sql
git commit -m "feat(db): 0002 RLS baseline, helpers, audit + auto-provisioning triggers"
```

---

### Task G: Migration 0003 — RBAC matrix seed

**Files:**
- Create: `supabase/migrations/0003_rbac_seed.sql`
- Test: `supabase/tests/0003_rbac_test.sql`

**Goal:** Seed `roles_permissions` with the full role × resource × action matrix over the 9 business resources, plus the `rbac_allows()` helper that Phase 1 uses in function guards and policies.

**Architecture:** SQL migration (idempotent `insert ... on conflict do nothing`) + psql DO-block test. Matrix (actions: READ/CREATE/UPDATE/DELETE):

| Role | Grants | Rows |
|---|---|---|
| PARISHIONER | READ on users, services, service_slots, bookings, payments, videos, video_purchases, announcements + CREATE bookings, complaints | 10 |
| PRIEST | READ all 9 + UPDATE all 9 (users, services, service_slots, bookings, payments, videos, video_purchases, complaints, announcements) | 18 |
| ADMIN | full CRUD on all 9 | 36 |
| SUPER_ADMIN | full CRUD on all 9 | 36 |

**Tech Stack:** PostgreSQL 16 (supabase local), plpgsql.

**Depends on:** Task F (0002 applied).

- [ ] **Step 1: Write the failing RBAC test**

Create `supabase/tests/0003_rbac_test.sql`:

```sql
\set ON_ERROR_STOP on
create schema if not exists tests;
create or replace function tests.expect(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if not p_cond then raise exception 'FAIL: %', p_msg; end if;
end $$;

do $$
declare t text; a text; r record;
begin
  foreach t in array array['users','services','service_slots','bookings','payments','videos',
                           'video_purchases','complaints','announcements'] loop
    foreach a in array array['READ','CREATE','UPDATE','DELETE'] loop
      perform tests.expect(
        exists (select 1 from public.roles_permissions
                where role = 'SUPER_ADMIN' and resource = t and action = a),
        'SUPER_ADMIN missing ' || a || ' on ' || t);
    end loop;
  end loop;

  perform tests.expect(
    (select count(*) from public.roles_permissions where role = 'SUPER_ADMIN') = 36,
    'SUPER_ADMIN must have exactly 36 rows');
  perform tests.expect(
    (select count(*) from public.roles_permissions where role = 'ADMIN') = 36,
    'ADMIN must have exactly 36 rows');
  perform tests.expect(
    (select count(*) from public.roles_permissions where role = 'PRIEST') = 18,
    'PRIEST must have exactly 18 rows');
  perform tests.expect(
    (select count(*) from public.roles_permissions where role = 'PARISHIONER') = 10,
    'PARISHIONER must have exactly 10 rows');
  perform tests.expect(
    (select count(*) from public.roles_permissions
     where role = 'PARISHIONER' and action = 'DELETE') = 0,
    'PARISHIONER must never DELETE');

  perform tests.expect(
    public.rbac_allows('PARISHIONER', 'services', 'READ') and
    public.rbac_allows('PARISHIONER', 'bookings', 'CREATE') and
    public.rbac_allows('PARISHIONER', 'complaints', 'CREATE'),
    'PARISHIONER key grants missing');
  perform tests.expect(
    public.rbac_allows('PRIEST', 'complaints', 'UPDATE') and
    public.rbac_allows('PRIEST', 'bookings', 'UPDATE') and
    public.rbac_allows('PRIEST', 'videos', 'READ'),
    'PRIEST key grants missing');
  perform tests.expect(
    public.rbac_allows('ADMIN', 'complaints', 'DELETE') and
    public.rbac_allows('SUPER_ADMIN', 'payments', 'DELETE'),
    'admin-level DELETE grants missing');
  perform tests.expect(
    not public.rbac_allows('PRIEST', 'payments', 'DELETE'),
    'PRIEST must not DELETE payments');
end $$;
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0003_rbac_test.sql`
Expected: FAIL — `SUPER_ADMIN missing READ on users` (table empty, `rbac_allows` does not exist yet).

- [ ] **Step 3: Write migration 0003**

Create `supabase/migrations/0003_rbac_seed.sql`:

```sql
-- 0003: RBAC matrix (9 resources x 4 actions). Phase 0 owns 0001-0003.

create or replace function public.rbac_allows(p_role public.app_role, p_resource text, p_action text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.roles_permissions rp
    where rp.role = p_role and rp.resource = p_resource and rp.action = p_action
  )
$$;

insert into public.roles_permissions (role, resource, action)
select 'PARISHIONER', u.resource, u.action from (values
  ('users','READ'),('services','READ'),('service_slots','READ'),('bookings','READ'),
  ('payments','READ'),('videos','READ'),('video_purchases','READ'),('announcements','READ'),
  ('bookings','CREATE'),('complaints','CREATE')
) as u(resource, action) on conflict do nothing;

insert into public.roles_permissions (role, resource, action)
select 'PRIEST', u.resource, u.action from (values
  ('users','READ'),('services','READ'),('service_slots','READ'),('bookings','READ'),
  ('payments','READ'),('videos','READ'),('video_purchases','READ'),('complaints','READ'),
  ('announcements','READ'),
  ('users','UPDATE'),('services','UPDATE'),('service_slots','UPDATE'),('bookings','UPDATE'),
  ('payments','UPDATE'),('videos','UPDATE'),('video_purchases','UPDATE'),('complaints','UPDATE'),
  ('announcements','UPDATE')
) as u(resource, action) on conflict do nothing;

insert into public.roles_permissions (role, resource, action)
select 'ADMIN', u.resource, u.action
from (select r.resource, a.action
      from (values ('users'),('services'),('service_slots'),('bookings'),('payments'),
                   ('videos'),('video_purchases'),('complaints'),('announcements')) as r(resource)
      cross join (values ('READ'),('CREATE'),('UPDATE'),('DELETE')) as a(action)
     ) u on conflict do nothing;

insert into public.roles_permissions (role, resource, action)
select 'SUPER_ADMIN', u.resource, u.action
from (select r.resource, a.action
      from (values ('users'),('services'),('service_slots'),('bookings'),('payments'),
                   ('videos'),('video_purchases'),('complaints'),('announcements')) as r(resource)
      cross join (values ('READ'),('CREATE'),('UPDATE'),('DELETE')) as a(action)
     ) u on conflict do nothing;
```

- [ ] **Step 4: Apply + run test, expect PASS**

Run: `supabase db reset; psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0003_rbac_test.sql`
Expected: `supabase db reset` exits 0 (0001–0003 applied); psql prints no output, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0003_rbac_seed.sql supabase/tests/0003_rbac_test.sql
git commit -m "feat(db): 0003 RBAC matrix seed (4 roles x 9 resources) + rbac_allows helper"
```

---

### Task H: Seed data + consolidated SQL regression suite

**Files:**
- Create: `supabase/seed.sql`
- Create: `supabase/tests/run_all.sql`

**Goal:** `supabase db reset` produces a demo database ready for Phase 1 development (its tests read "seeded rows to anon"): 4 auth users with matching `public.users` profiles across roles (ADMIN, 2× PARISHIONER, PRIEST), 2 services with 3 future OPEN slots, 2 priests, 1 announcement, and FAQ rows once Phase 1 0004 creates `faq`. `run_all.sql` is the single entry point CI and humans use for the whole SQL suite.

**Architecture:** `supabase db reset` runs migrations (0001–0003) then `supabase/seed.sql` automatically. Seed is idempotent (`on conflict do nothing` / `if count = 0` guards) and must not fail when `faq` does not exist yet (`to_regclass` guard). Users sign in via phone OTP only in Phase 1 — the auth rows here just provision profiles; local OTP codes are printed in the auth container logs (no real SMS until Task I wires Twilio env vars).

**Tech Stack:** PostgreSQL 16 (supabase local), psql `\ir` includes.

**Depends on:** Tasks E–G (0001–0003 applied).

- [ ] **Step 1: Write `supabase/seed.sql`**

```sql
-- supabase/seed.sql: demo data for local dev. Runs automatically after
-- migrations on `supabase db reset`. Idempotent.

insert into auth.users (id, instance_id, aud, role, email, phone,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'admin@church.test', '+201000000001',
   '{}', '{"name":"مدير النظام"}', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'mariam@church.test', '+201000000002',
   '{}', '{"name":"مريم جورج"}', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'peter@church.test', '+201000000003',
   '{}', '{"name":"بيتر عادل"}', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'priest@church.test', '+201000000004',
   '{}', '{"name":"أب كيرلس"}', now(), now())
on conflict (id) do nothing;

-- handle_new_user (0002) already inserted profiles; upsert pins roles + names
insert into public.users (id, phone, name, role, tenant_id)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', '+201000000001', 'مدير النظام', 'ADMIN', 1),
  ('aaaaaaaa-0000-0000-0000-000000000002', '+201000000002', 'مريم جورج', 'PARISHIONER', 1),
  ('aaaaaaaa-0000-0000-0000-000000000003', '+201000000003', 'بيتر عادل', 'PARISHIONER', 1),
  ('aaaaaaaa-0000-0000-0000-000000000004', '+201000000004', 'أب كيرلس', 'PRIEST', 1)
on conflict (id) do update set name = excluded.name, role = excluded.role;

do $$
begin
  if (select count(*) from public.services) = 0 then
    insert into public.services (title_ar, description, schedule, location, tenant_id)
    values ('قداس الأحد', 'القداس الأسبوعي', '{"weekly":true,"day":0,"time":"08:00"}'::jsonb, 'الكنيسة الرئيسية', 1),
           ('قداس العيد', 'قداس الأعياد السيدية', '{"special":true}'::jsonb, 'الكنيسة الرئيسية', 1);

    insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, tenant_id)
    values ((select id from public.services where title_ar = 'قداس الأحد'),
            now() + interval '2 days', now() + interval '2 days' + interval '1 hour', 50, 0, 1),
           ((select id from public.services where title_ar = 'قداس الأحد'),
            now() + interval '3 days', now() + interval '3 days' + interval '1 hour', 50, 0, 1),
           ((select id from public.services where title_ar = 'قداس العيد'),
            now() + interval '7 days', now() + interval '7 days' + interval '2 hours', 80, 20, 1);
  end if;

  if (select count(*) from public.priests) = 0 then
    insert into public.priests (name, bio, visitation_hours, tenant_id)
    values ('أب كيرلس', 'خادم الرعية', '{"tue":"18:00-20:00"}'::jsonb, 1),
           ('أب مكاري', 'خادم الرعية', '{"sat":"17:00-19:00"}'::jsonb, 1);
  end if;

  if (select count(*) from public.announcements) = 0 then
    insert into public.announcements (title_ar, body_ar, published_at, tenant_id)
    values ('اجتماع الخدام', 'الخميس الساعة 8 مساءً', now() + interval '3 days', 1);
  end if;

  -- faq is created by Phase 1 0004: seed must run cleanly before AND after it
  if to_regclass('public.faq') is not null and not exists (select 1 from public.faq) then
    insert into public.faq (question_ar, answer_ar)
    values ('كيف أحجز قداساً؟', 'من صفحة الخدمات'),
           ('كيف أدفع؟', 'فودافون كاش أو من الكنيسة'),
           ('هل يمكن الإلغاء؟', 'نعم، قبل 24 ساعة من الموعد');
  end if;
end $$;
```

NOTE: when Phase 1 0004 lands, confirm `faq` column names in the seed match the 0004 definition (they must — this seed block stays inactive until then). No code changes here either way.

- [ ] **Step 2: Write `supabase/tests/run_all.sql`**

```sql
-- supabase/tests/run_all.sql: consolidated SQL regression suite.
\set ON_ERROR_STOP on
\ir 0000_health_test.sql
\ir 0001_schema_test.sql
\ir 0002_rls_test.sql
\ir 0003_rbac_test.sql
```

- [ ] **Step 3: Reset + run full suite, expect PASS**

Run: `supabase db reset; psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/run_all.sql`
Expected: `supabase db reset` exits 0 (0001–0003 + seed); psql prints no output, exit code 0.

- [ ] **Step 4: Spot-check the demo data**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "select p.phone, p.role from public.users p order by p.phone;"`
Expected: 4 rows — `+201000000001` ADMIN, `+201000000002/3` PARISHIONER, `+201000000004` PRIEST.

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "select count(*) from public.service_slots where status = 'OPEN' and starts_at > now();"`
Expected: 3.

- [ ] **Step 5: Commit**

```bash
git add supabase/seed.sql supabase/tests/run_all.sql
git commit -m "feat(db): demo seed data + consolidated SQL regression suite (run_all)"
```

---

### Task I: Auth wiring — phone OTP login screens (both apps)

**Files:**
- Edit: `supabase/config.toml`, create `.env` (gitignored)
- Create (mobile): `apps/mobile/lib/core/auth/auth_gateway.dart`, `apps/mobile/lib/features/auth/login_screen.dart`, `apps/mobile/lib/features/auth/otp_screen.dart`, `apps/mobile/test/features/auth/login_screen_test.dart`, `apps/mobile/test/features/auth/otp_screen_test.dart`
- Create (admin, mirrored): `apps/admin/lib/core/auth/auth_gateway.dart`, `apps/admin/lib/features/auth/login_screen.dart`, `apps/admin/lib/features/auth/otp_screen.dart`, `apps/admin/test/features/auth/login_screen_test.dart`, `apps/admin/test/features/auth/otp_screen_test.dart`

**Goal:** A phone-OTP login flow in both apps (Arabic-first, RTL), wired to Supabase Auth, and a Twilio placeholder in `config.toml` so Phase 1 can flip on real SMS without schema work. Local dev receives OTP codes from the auth container logs (no real SMS is sent without Twilio credentials).

**Architecture:** A small `AuthGateway` abstraction over `SupabaseClient.auth` (hand-injected, so widget tests use a fake). Login = phone entry screen → `signInWithOtp(phone)` → OTP screen → `verifyOtp(phone, token)`. Screens are RTL with Arabic labels. `config.toml` gains `[auth.sms]` + `[auth.sms.provider.twilio]` reading env vars so no secrets live in the repo.

**Tech Stack:** Flutter, supabase_flutter, Riverpod (already in Task C scaffolds).

**Depends on:** Task C (apps exist and pass smoke tests).

- [ ] **Step 1: Write the failing login-screen test (mobile)**

Create `apps/mobile/test/features/auth/login_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_gateway.dart';
import 'package:mobile/features/auth/login_screen.dart';

class FakeAuthGateway implements AuthGateway {
  final otpCalls = <String>[];
  bool sendSucceeds = true;

  @override
  Future<void> sendOtp(String phone) async {
    if (!sendSucceeds) throw Exception('sms-failed');
    otpCalls.add(phone);
  }

  @override
  Future<bool> verifyOtp(String phone, String token) async => true;
}

void main() {
  testWidgets('renders phone field and sends OTP', (tester) async {
    final gateway = FakeAuthGateway();
    var navigated = false;
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(
        gateway: gateway,
        onOtpSent: (phone) => navigated = true,
      ),
    ));

    expect(find.text('تسجيل الدخول'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '01000000002');
    await tester.tap(find.text('إرسال الرمز'));
    await tester.pump();

    expect(gateway.otpCalls, ['01000000002']);
    expect(navigated, isTrue);
  });

  testWidgets('shows validation error for short phone', (tester) async {
    final gateway = FakeAuthGateway();
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(gateway: gateway, onOtpSent: (_) {}),
    ));

    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('إرسال الرمز'));
    await tester.pump();

    expect(find.text('رقم غير صحيح'), findsOneWidget);
    expect(gateway.otpCalls, isEmpty);
  });

  testWidgets('shows error message when SMS send fails', (tester) async {
    final gateway = FakeAuthGateway()..sendSucceeds = false;
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(gateway: gateway, onOtpSent: (_) {}),
    ));

    await tester.enterText(find.byType(TextField), '01000000002');
    await tester.tap(find.text('إرسال الرمز'));
    await tester.pumpAndSettle();

    expect(find.text('تعذر إرسال الرمز'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it, expect FAIL**

Run (workdir `apps/mobile`): `flutter test test/features/auth/login_screen_test.dart`
Expected: compile error — `AuthGateway`/`LoginScreen` do not exist.

- [ ] **Step 3: Implement the mobile gateway + login screen**

Create `apps/mobile/lib/core/auth/auth_gateway.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AuthGateway {
  Future<void> sendOtp(String phone);
  Future<bool> verifyOtp(String phone, String token);
  Future<void> signOut();
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<void> sendOtp(String phone) =>
      _client.auth.signInWithOtp(phone: phone);

  @override
  Future<bool> verifyOtp(String phone, String token) async {
    try {
      final response = await _client.auth.verifyOTP(
        type: OtpType.sms,
        phone: phone,
        token: token,
      );
      return response.session != null;
    } on AuthException {
      return false;
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
```

Create `apps/mobile/lib/features/auth/login_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:mobile/core/auth/auth_gateway.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.gateway, required this.onOtpSent});
  final AuthGateway gateway;
  final void Function(String phone) onOtpSent;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  bool _sending = false;

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _sending = true);
    try {
      await widget.gateway.sendOtp(_phone.text.trim());
      widget.onOtpSent(_phone.text.trim());
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر إرسال الرمز')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('تسجيل الدخول', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                SizedBox(
                  width: 280,
                  child: TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      hintText: '01xxxxxxxxx',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().length < 10) ? 'رقم غير صحيح' : null,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _sending ? null : _submit,
                  child: const Text('إرسال الرمز'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test, expect PASS**

Run (workdir `apps/mobile`): `flutter test test/features/auth/login_screen_test.dart`
Expected: all 3 tests pass.

- [ ] **Step 5: OTP screen + test (mobile)**

Create `apps/mobile/test/features/auth/otp_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_gateway.dart';
import 'package:mobile/features/auth/otp_screen.dart';

class FakeAuthGateway implements AuthGateway {
  bool acceptCode = true;
  String? receivedToken;

  @override
  Future<void> sendOtp(String phone) async {}

  @override
  Future<bool> verifyOtp(String phone, String token) async {
    receivedToken = token;
    return acceptCode;
  }

  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('verifies OTP and reports success', (tester) async {
    final gateway = FakeAuthGateway();
    var signedIn = false;
    await tester.pumpWidget(MaterialApp(
      home: OtpScreen(
        phone: '01000000002',
        gateway: gateway,
        onVerified: () => signedIn = true,
      ),
    ));

    expect(find.text('رمز التحقق'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();

    expect(gateway.receivedToken, '123456');
    expect(signedIn, isTrue);
  });

  testWidgets('shows error for wrong code', (tester) async {
    final gateway = FakeAuthGateway()..acceptCode = false;
    await tester.pumpWidget(MaterialApp(
      home: OtpScreen(phone: '01000000002', gateway: gateway, onVerified: () {}),
    ));

    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();

    expect(find.text('الرمز غير صحيح'), findsOneWidget);
  });
}
```

Create `apps/mobile/lib/features/auth/otp_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:mobile/core/auth/auth_gateway.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.phone,
    required this.gateway,
    required this.onVerified,
  });
  final String phone;
  final AuthGateway gateway;
  final VoidCallback onVerified;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  bool _verifying = false;

  Future<void> _verify() async {
    setState(() => _verifying = true);
    final ok = await widget.gateway.verifyOtp(widget.phone, _code.text.trim());
    if (!mounted) return;
    setState(() => _verifying = false);
    if (ok) {
      widget.onVerified();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرمز غير صحيح')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('رمز التحقق')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('أدخل الرمز المرسل إلى ${widget.phone}'),
              const SizedBox(height: 16),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '6 أرقام',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _verifying ? null : _verify,
                child: const Text('تأكيد'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Run (workdir `apps/mobile`): `flutter test test/features/auth/` — expected: all 5 tests pass.

- [ ] **Step 6: Mirror screens in the admin app**

Copy the 4 mobile files to the admin app (same paths under `apps/admin/`, package `admin`), renaming imports from `package:mobile/...` to `package:admin/...`, keeping every widget/string identical (admin staff reuse the same phone-OTP flow). Run (workdir `apps/admin`): `flutter test test/features/auth/` — expected: all 5 pass.

- [ ] **Step 7: Wire Supabase config (SMS placeholder)**

Edit `supabase/config.toml` — under the existing `[auth]` block add:

```toml
[auth.sms]
enable_signup = true

[auth.sms.provider.twilio]
enabled = true
account_sid = "env(TWILIO_ACCOUNT_SID)"
auth_token = "env(TWILIO_AUTH_TOKEN)"
message_service_sid = "env(TWILIO_MESSAGE_SERVICE_SID)"
```

Create `.env` (repo root, gitignored — `.gitignore` from Task B already covers it):

```
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_MESSAGE_SERVICE_SID=
```

Run: `supabase start` (restart the auth container: `supabase stop; supabase start`)
Expected: stack starts green. With empty Twilio env vars, no SMS leaves the machine; OTP codes are printed to the auth container logs: `supabase logs` (filter for `otp`).

- [ ] **Step 8: Manual smoke test**

Run the mobile app (workdir `apps/mobile`): `flutter run -d windows` (or an Android emulator). In the app: enter `+201000000002` → request code → read the code from `supabase logs` → enter it. Expected: login completes; `public.users` shows the row for that phone with `role = PARISHIONER` (auto-provisioned by the 0002 trigger).

- [ ] **Step 9: Commit**

```bash
git add supabase/config.toml .env apps/mobile/lib/core/auth apps/mobile/lib/features/auth apps/mobile/test/features/auth apps/admin/lib/core/auth apps/admin/lib/features/auth apps/admin/test/features/auth
git commit -m "feat(auth): phone OTP login screens (mobile + admin) with Twilio placeholder config"
```

---

### Task J: CI workflow (GitHub Actions)

**File:**
- Create: `.github/workflows/ci.yml` (+ `supabase/functions/.gitkeep` so the functions dir exists for the deno job)

**Goal:** Every PR runs the Flutter suites and the SQL regression suite; `main` additionally deploys the schema to staging (requires repo secrets).

**Architecture:** Five jobs: `flutter-mobile`, `flutter-admin` (analyze + test), `sql-tests` (supabase start → db reset → run_all.sql via docker exec), `deno-tests` (check functions, no-op until Phase 1 adds functions), `deploy-staging` (link + `db push`, gated on `main` and secrets).

**Tech Stack:** GitHub Actions, supabase/setup-cli, subosito/flutter-action, denoland/setup-deno.

**Depends on:** Tasks B–I (repo, apps, migrations, seed, tests all exist).

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  flutter-mobile:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: apps/mobile
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test

  flutter-admin:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: apps/admin
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test

  sql-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v1
        with:
          version: latest
      - name: Start local stack
        run: supabase start
      - name: Apply migrations + seed
        run: supabase db reset
      - name: Run SQL regression suite
        run: |
          DB=$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1)
          docker exec -i "$DB" psql -U postgres -d postgres < supabase/tests/run_all.sql

  deno-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: denoland/setup-deno@v2
        with:
          deno-version: v2.x
      - name: Check edge functions (no-op until Phase 1)
        run: |
          if [ -n "$(ls -A supabase/functions 2>/dev/null | grep -v '^.gitkeep$')" ]; then
            deno check $(find supabase/functions -name '*.ts' -not -name '*_test.ts')
          fi

  deploy-staging:
    needs: [flutter-mobile, flutter-admin, sql-tests]
    if: github.ref == 'refs/heads/main'
    environment: staging
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v1
        with:
          version: latest
      - run: supabase link --project-ref ${{ secrets.SUPABASE_PROJECT_REF }}
      - run: supabase db push
      - name: Deploy edge functions (no-op until Phase 1)
        run: |
          if [ -n "$(ls -A supabase/functions 2>/dev/null | grep -v '^.gitkeep$')" ]; then
            supabase functions deploy --project-ref ${{ secrets.SUPABASE_PROJECT_REF }}
          fi
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
```

Also create `supabase/functions/.gitkeep` (empty file, so git tracks the directory).

- [ ] **Step 2: Push and verify**

Run: `git add .github/workflows/ci.yml supabase/functions/.gitkeep; git commit -m "ci: flutter + SQL + deno checks, staging deploy"; git push`
Expected: GitHub Actions shows 4 jobs on the push (deploy-staging runs only on `main`): `flutter-mobile`, `flutter-admin`, `sql-tests` (exit 0 — suite green), `deno-tests` (no-op). Add repo secrets (`SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`) and a `staging` environment to enable the deploy job.

---

### Task K: Phase 0 definition-of-done

**Goal:** Explicit sign-off gates so Phase 1 starts from a verified foundation.

- [ ] `supabase start` and `supabase db reset` exit 0 — migrations 0001–0003 + seed apply cleanly (Task D–H).
- [ ] `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/run_all.sql` passes with zero output (0000 health, 0001 schema, 0002 RLS, 0003 RBAC).
- [ ] PostgREST sanity check as anon returns `[]` everywhere: `curl -H "apikey: <anon key from Task D>" http://127.0.0.1:54321/rest/v1/bookings` returns `[]` (and same for `users`).
- [ ] Phone-OTP login works in both apps against the local stack (code read from `supabase logs`) — Task I.
- [ ] `flutter analyze` and `flutter test` are green in both apps (Task C + I).
- [ ] CI shows `flutter-mobile`, `flutter-admin`, `sql-tests`, `deno-tests` passing on the latest push (Task J).
- [ ] `docs/external-onboarding-checklist.md` (Task A) reviewed and shared with church admins.
- [ ] Staging project exists and `supabase db push` succeeds from CI on `main` (Task J).

**Phase 1 entry conditions (handoff):** schema at 0003 + seed, RLS baseline with `p0_` policies, `tenant_id()`/`current_user_role()`/`rbac_allows()`/`audit_trigger()` helpers, auth flow live in both apps, CI green. Phase 1 continues with migrations 0004+ — its `create table if not exists` guards and policy names cannot collide with this baseline by construction (0001 names match §5 exactly; policies are `p0_`-prefixed; helpers are `create or replace`-safe).
