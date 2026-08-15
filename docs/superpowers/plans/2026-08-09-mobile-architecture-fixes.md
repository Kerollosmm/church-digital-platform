# Mobile Architecture Fixes — Implementation Plan

**Date:** 2026-08-09 · **Supersedes:** `docs/superpowers/analysis/2026-08-09-architecture-deepening.md`
**Note on discrepancies:** analysis doc diverges from the real repo (no `tenants` table, no `service_settings`, different booking statuses). Migrations win; every RPC/view/column below copied from `supabase/migrations/0001–0023`.
**Scope:** `apps/mobile` (Flutter). No backend dependency: all RPCs below exist today (`book_slot`, `cancel_booking`, `confirm_booking`, `complete_booking`, `join_waiting_list`, `purchase_video`, `submit_complaint_secure` lands in backend Task 3).
**Workflow:** test-first per task (failing test → implement → run → PASS → commit). Commits: `(mobile) fix: <summary>`.

## Objective

Layered, testable architecture: UI → controllers → repository interface → Supabase impl. One booking-status model mirroring the DB. No client-side lock math (server `expire_stale_bookings` cron owns locks). One typed error mapper with Arabic messages. GoRouter with named routes (kills the "stuck on nested navigator" flows). Delete Provider. Full offline `flutter test` suite with fakes.

## Architecture

- **Layers:** `lib/ui/` (screens/widgets) → `lib/controllers/` (no `supabase_flutter` imports) → `lib/repositories/` (interface + `SupabaseBookingRepository`) → `lib/models/` (plain models) → `lib/services/` (`app_supabase.dart`, `service_locator.dart`, `error_mapper.dart`, `app_strings.dart`, `router.dart`, `routes.dart`).
- **Single status model** `models/booking_status.dart`: exactly the DB enum — `PENDING_PAYMENT, AWAITING_CALL, CONFIRMED, COMPLETED, CANCELLED, RESCHEDULED` (no `noShow`/`refundPending`/`expired` — they don't exist). `ResolvedBookingStatus` (Arabic label + color + sort weight) in `models/resolved_booking_status.dart`. Delete the legacy app enum + `statusOptions`-style maps + ternary color/label logic.
- **`BookSlotResult`** — `BookSlotStatus { success, slotUnavailable, slotFull, alreadyBooked, tooManyActive, unknown }` + message + booking. Codes mapped from `0008_booking_state_machine.sql`: `SLOT_UNAVAILABLE`, `SLOT_FULL`, `ALREADY_BOOKED_SLOT`, `TOO_MANY_ACTIVE_BOOKINGS`, `FORBIDDEN` (42501), `AUTH_REQUIRED` (28000). `book_slot(slot_id, opt_in)` — **no seats parameter**; capacity counts bookings (multi-seat Mass slots = multiple booking rows).
- **No client-side locks:** `locked_until` is server-only (0008/0010). On `slotFull`/`alreadyBooked`/`slotUnavailable`: show mapped Arabic message, refresh `v_available_slots`. Delete any `locked_until`/lock-age UI + `expire`/`dismiss lock` widgets.
- **Admin ops:** call the existing RPCs — `cancel_booking`, `confirm_booking`, `complete_booking` (backend Task 1 reroutes them through the transition engine; mobile contract unchanged). `requestCall` → `apply_payment` is webhook-driven; the app instead shows "سيتم التواصل معك" after payment.
- **Errors:** `SupabaseApiException(kind, code, message, userMessage, originalError)` + `mapSupabaseError(Object, {required String context})` mapping `PostgrestException` (PGRST codes + SQLSTATE `P0001` + message prefixes `SLOT_*`/`ALREADY_*`/`FORBIDDEN`/`BOOKING_NOT_FOUND`/`PAYMENT_NOT_FOUND`), `AuthException`, `SocketException`/`TimeoutException`, `FormatException`. Arabic strings centralized in `app_strings.dart`; controllers use `runGuarded(...)` → SnackBar.
- **Navigation:** `go_router`; named routes; `ShellRoute` for the tab scaffold; route guards on session; payment sheet = pushed route (web back works).
- **DI:** manual container `AppDependencies { supabase, bookingRepository, videoRepository, announcementsRepository, router }` + `forTest(...)`; constructor injection; no `provider`.

## Task List

| # | Deliverable |
|---|---|
| 1 | Layered skeleton: models/, repositories/ (interface + supabase impl), controllers/, service_locator |
| 2 | Booking status consolidation + BookSlotResult (real error codes) |
| 3 | Error mapper + SupabaseApiException + Arabic strings |
| 4 | GoRouter named-route tree + safe navigation |
| 5 | DI wiring + Provider removal |
| 6 | Offline test suite with fakes |

---

## Task 1 — Layered skeleton + repository interface

**Context:** screens/controllers currently import `supabase_flutter` directly and `main.dart` wires everything inline. Cut the seams.

### Step 1 — failing widget test `apps/mobile/test/widget/dashboard_smoke_test.dart`

```dart
testWidgets('dashboard renders bookings from fake repository', (tester) async {
  final fake = FakeBookingRepository(bookings: [fakeResolvedBooking]);
  await tester.pumpWidget(TestApp(deps: AppDependencies.forTest(bookingRepository: fake)));
  expect(find.text(fakeResolvedBooking.serviceName!), findsOneWidget);
});
```
Fails: `DashboardScreen(repository: ...)` doesn't exist.

### Step 2 — create skeleton

- `models/` — move existing plain model classes unchanged; strip `supabase_flutter` types from them.
- `repositories/booking_repository.dart`:
```dart
abstract interface class BookingRepository {
  Future<List<AvailableSlot>> fetchAvailableSlots();
  Future<List<Booking>> fetchMyBookings();
  Future<BookSlotResult> bookSlot({required int slotId, required bool optIn});
  Future<void> cancelBooking(int bookingId);
  Future<void> confirmBooking(int bookingId);
  Future<void> completeBooking(int bookingId);
}
```
- `repositories/supabase_booking_repository.dart` — implements it over `AppSupabase`:
  - `fetchAvailableSlots` → `from('v_available_slots').select()` ordered `starts_at`.
  - `fetchMyBookings` → `from('bookings').select()` with `p0_bookings_read_own` (own rows only).
  - `bookSlot` → `rpc('book_slot', {p_slot_id, p_opt_in})`; `PostgrestException.message` prefix → `BookSlotStatus` (Task 2); success row → `Booking.fromJson`.
  - `cancelBooking/confirmBooking/completeBooking` → `rpc('cancel_booking'|'confirm_booking'|'complete_booking', {p_booking_id})`.
- `controllers/dashboard_controller.dart`, `controllers/booking_flow_controller.dart` — take `BookingRepository` via constructor; no Supabase imports.
- `services/app_supabase.dart`:
```dart
abstract interface class AppSupabase {
  Future<Object> rpc(String fn, Map<String, dynamic> params);
  Future<List<Map<String, dynamic>>> query(String table, Map<String, dynamic> filters);
}
```
`SupabaseAppSupabase` wraps `Supabase.instance` (rpc → `.rpc(fn, params).data`; query → `.from(table).select().match(filters).data`). `TestAppSupabase` in `test/helpers/` (programmable).
- `services/service_locator.dart` — `AppDependencies` + `forTest`.

### Step 3 — run → PASS → commit `(mobile) fix: layered skeleton + repository seam`

---

## Task 2 — Booking status consolidation + BookSlotResult

**Context:** the app enum diverges from the DB enum (has `noShow`, `refundPending`, `expired` that don't exist in `0001`), plus per-widget ternary label/color maps.

### Step 1 — failing unit test `apps/mobile/test/unit/booking_status_test.dart`

```dart
test('resolver covers every db status', () {
  for (final s in BookingStatus.values) {
    final r = resolveBookingStatus(s);
    expect(r.label, isNotEmpty);
    expect(r.color, isNotNull);
    expect(r.sortWeight, isA<int>());
  }
});
test('bookSlot maps real error codes', () {
  expect(bookSlotErrorCode('SLOT_UNAVAILABLE'), BookSlotStatus.slotUnavailable);
  expect(bookSlotErrorCode('SLOT_FULL'), BookSlotStatus.slotFull);
  expect(bookSlotErrorCode('ALREADY_BOOKED_SLOT'), BookSlotStatus.alreadyBooked);
  expect(bookSlotErrorCode('TOO_MANY_ACTIVE_BOOKINGS'), BookSlotStatus.tooManyActive);
  expect(bookSlotErrorCode('anything else'), BookSlotStatus.unknown);
});
```

### Step 2 — implement

- `models/booking_status.dart` — `enum BookingStatus { pendingPayment, awaitingCall, confirmed, completed, cancelled, rescheduled }` with DB-string mapping (`PENDING_PAYMENT`…). Delete the old app enum + `BookingStatusOptions`; grep `BookingStatus|statusOptions` → only this file + resolver + repo.
- `models/resolved_booking_status.dart` — `class ResolvedBookingStatus { final String label; final MaterialColor color; final int sortWeight; }` + `resolveBookingStatus(BookingStatus)`. Arabic labels: `في انتظار الدفع`, `بانتظار الاتصال`, `مؤكد`, `مكتمل`, `ملغي`, `أعيدت جدولته`. Colors: confirmed green, completed grey, cancelled red, awaitingCall amber, pendingPayment amber, rescheduled blue.
- `models/book_slot_result.dart` — `enum BookSlotStatus { success, slotUnavailable, slotFull, alreadyBooked, tooManyActive, unknown }`, `class BookSlotResult { status, message, booking }`, `BookSlotStatus bookSlotErrorCode(String messagePrefix)` (case-insensitive `contains` on the message, per the P0001 prefixes above).
- `controllers/booking_flow_controller.dart` — `slotUnavailable/slotFull/alreadyBooked/tooManyActive` → mapped Arabic message + refresh slots; **delete all `locked_until`/lock-age/stale-lock UI** (grep `locked_until|staleLock|lockExpired|expire` in `lib/` + `test/` → remove).
- `repositories/supabase_booking_repository.dart` — wire `bookSlotErrorCode` into `bookSlot`.

### Step 3 — run → PASS → commit `(mobile) fix: single booking status model + real error codes`

---

## Task 3 — Error mapping

**Context:** `catch (e) { SnackBar(raw English text) }` scattered; PostgREST messages shown verbatim.

### Step 1 — failing unit test `apps/mobile/test/unit/error_mapper_test.dart`

```dart
test('maps PostgrestException PGRST202', () {
  final e = PostgrestException(message: 'rpc function book_slot not found', code: 'PGRST202');
  final m = mapSupabaseError(e, context: 'book_slot');
  expect(m, isA<SupabaseApiException>());
  expect(m.code, 'PGRST202');
  expect(m.userMessage, contains('غير متاح'));
});
test('maps SLOT_FULL SQLSTATE P0001', () { /* userMessage contains 'ممتلئ' */ });
test('maps FORBIDDEN', () { /* 'لا تملك صلاحية' */ });
test('maps AuthException invalid login', () { /* 'بيانات الدخول غير صحيحة' */ });
test('maps SocketException offline', () { /* 'تعذّر الاتصال بالإنترنت' */ });
test('maps unknown/FormatException', () { /* 'حدث خطأ غير متوقع' */ });
```

### Step 2 — implement

- `services/error_mapper.dart` — `enum AppErrorKind { network, auth, forbidden, notFound, conflict, server, validation, unknown }`; `class SupabaseApiException implements Exception { kind, code, message, userMessage, originalError }`; `SupabaseApiException mapSupabaseError(Object error, {required String context})`:
  - `PostgrestException`: `PGRST204`/`PGRST116` → notFound; `PGRST202` → server; message prefix `FORBIDDEN` → forbidden; `BOOKING_NOT_FOUND`/`PAYMENT_NOT_FOUND`/`USER_NOT_FOUND`/`VIDEO_NOT_FOUND` → notFound; `SLOT_*`/`ALREADY_*`/`TOO_MANY_*` → conflict (mapped again by `bookSlotErrorCode` where relevant); else server.
  - `AuthException`: invalid-credentials/expired → auth ("جلسة منتهية، سجّل الدخول مجدداً").
  - `SocketException`/`TimeoutException` → network.
  - anything else → unknown.
- `services/app_strings.dart` — Arabic strings table; move inline SnackBar literals in screens to constants.
- `controllers/run_guarded.dart` — `Future<void> runGuarded(Future<void> Function() body, {required void Function(String message) onError})` wrapping `mapSupabaseError`; controllers/screens use it for every network call.

### Step 3 — run → PASS → commit `(mobile) fix: typed supabase error mapping`

---

## Task 4 — GoRouter + safe navigation

**Context:** booking flow and admin flows get stuck on nested navigators (web back button loses state). Fix with a single router tree.

### Step 1 — failing widget test `apps/mobile/test/widget/router_test.dart`

```dart
testWidgets('deep link to booking detail renders with route guard', (tester) async {
  final router = buildAppRouter(deps: depsForTest(session: fakeSession));
  await tester.pumpWidget(TestApp(router: router));
  router.goNamed(Routes.bookingDetail, params: {'id': '5'});
  await tester.pumpAndSettle();
  expect(find.text('مؤكد'), findsOneWidget);
});
testWidgets('unauthenticated deep link redirects to login', ...);
```

### Step 2 — implement

- `services/routes.dart` — `class Routes { static const login='login'; home='home'; dashboard='dashboard'; bookings='bookings'; videos='videos'; profile='profile'; bookingDetail='bookingDetail'; bookingFlow='bookingFlow'; admin='admin'; videoWatch='videoWatch'; }`.
- `services/router.dart` — `GoRouter buildAppRouter(AppDependencies deps)`:
  - `/login`; `/home` → `ShellRoute` (bottom nav: dashboard, bookings, videos, profile); `/booking/:id`; `/booking/new` (slot → opt-in → payment sheet as pushed route); `/admin` (slots, manual booking, emergency override, export, complaints); `/videos/:id`.
  - Guards: `refreshListenable` on session state from `AppSupabase`; `redirect` unauthenticated → `/login`.
- Replace `Navigator.push`/nested `Navigator` in screens with `context.goNamed`/`context.pushNamed`; after booking success → `context.goNamed(Routes.bookingDetail, params: {'id': '${id}'})`.
- Controllers navigate via injected `GoRouter` (from deps), not `context`.

### Step 3 — run → PASS → commit `(mobile) fix: go_router navigation tree`

---

## Task 5 — DI wiring + Provider removal

### Step 1 — failing widget test `apps/mobile/test/widget/app_bootstrap_test.dart`

```dart
testWidgets('app boots with test dependencies, no Provider, no network', (tester) async {
  final deps = AppDependencies.forTest(supabase: fakeAppSupabase, bookingRepository: fakeRepo, router: testRouter);
  await tester.pumpWidget(ChurchApp(dependencies: deps));
  expect(find.byType(BottomNavScaffold), findsOneWidget);
});
```

### Step 2 — implement

- `main.dart` — `runApp(ChurchApp(dependencies: AppDependencies.live()))`; `ChurchApp` = `MaterialApp.router(routerConfig: deps.router, locale: Locale('ar'), supportedLocales: [Locale('ar')], theme: ..., debugShowCheckedModeBanner: false)`.
- `services/service_locator.dart` — manual container; `AppDependencies.live()` builds `SupabaseAppSupabase` + repos + router; `forTest(...)` builds fakes; no static singletons except the container instance itself.
- `pubspec.yaml` — remove `provider`; ensure `go_router` present; keep `supabase_flutter`, `intl`.
- Grep `Provider.of|Consumer<|ChangeNotifierProvider|MultiProvider` in `lib/` → zero.
- `test/helpers/` — `FakeAppSupabase` (records `rpc`/`query` calls; programmable responses + failure injection), `FakeBookingRepository`, `TestApp`, `fakeResolvedBooking`, `fakeSession`.

### Step 3 — run → PASS → commit `(mobile) fix: constructor DI, remove provider`

---

## Task 6 — Offline test suite

**Context:** tests must not touch the network or a real Supabase instance.

### Step 1 — failing tests (add per area)

- `test/unit/booking_status_test.dart` (Task 2 — every enum value + all 5 error-code mappings)
- `test/unit/error_mapper_test.dart` (Task 3)
- `test/unit/supabase_booking_repository_test.dart` — rpc call params asserted: `book_slot` `{p_slot_id, p_opt_in}`; `cancel_booking`/`confirm_booking`/`complete_booking` `{p_booking_id}`; `book_slot` success → `BookSlotResult.success` with parsed booking; `SLOT_FULL` → `slotFull`; rpc throws → `SupabaseApiException` propagated; `fetchMyBookings` → `query('bookings', {})`.
- `test/widget/dashboard_test.dart` — renders resolved statuses (Arabic label + color chip), empty state, error state (failure-injected fake → mapped Arabic message SnackBar).
- `test/widget/booking_flow_test.dart` — full flow: slot list (from `v_available_slots` fake) → select → opt-in → payment sheet route pushed → success → `goNamed(bookingDetail)`; `slotFull` path shows Arabic message + refreshes; no lock math anywhere.
- `test/widget/admin_booking_ops_test.dart` — confirm/cancel/complete buttons call repo methods; success updates UI via resolver.
- `test/widget/router_test.dart` (Task 4).

### Step 2 — make green (fakes in `test/helpers/`; delete live-network test helpers)

### Step 3 — run `flutter test` (offline) + `flutter analyze` → PASS → commit `(mobile) fix: offline test suite`

---

## Verification checklist

- `flutter analyze` 0 issues; `flutter test` all green offline
- Greps zero in `lib/`: `Provider|locked_until|staleLock|statusOptions|BookingStatusOptions|noShow|refundPending|expired`
- No `supabase_flutter` imports outside `repositories/`, `services/app_supabase.dart`, `services/error_mapper.dart`
- Every network-touching controller path covered by a fake-backed test
- Manual smoke (local stack up): login → book → pay stub → detail shows `في انتظار الدفع` → admin confirms → `مؤكد`

## Risks / notes

- RTL: Arabic strings live only in `app_strings.dart`; screens never hardcode messages.
- Keep `BookSlotResult` mapping in the repo layer; controllers stay Supabase-free.
- Backend Task 4 changes `whatsapp_outbox` → `event_outbox` and backend Task 1 reroutes lifecycle RPCs internally — mobile RPC names (`book_slot`, `cancel_booking`, `confirm_booking`, `complete_booking`, `join_waiting_list`, `purchase_video`) are unchanged by both.
