# Round-2 Review Follow-Ups: LOW-Severity Backlog

**Date**: 2026-09-05
**Source**: Remaining LOW-severity findings from the 2026-09-04 Gemini full-codebase review (round-1 CRITICAL/HIGH fixes landed in commit `6163073`).
**Mode**: External agent (agy) implements; orchestrator verifies and lands.

## Goal

Close out the LOW-severity backlog: dead code deletion (admin screens, diagnostic engine), UI dedup, Arabic localization of analytics screens, repository-seam fix for the export button, and two build-method decompositions. **No behavior changes** except where a task explicitly says so (error messages that were swallowed/English now surface in Arabic).

## Global guardrails

- Never edit existing migrations; no DB changes in this round (nothing here touches the database).
- Never weaken tests to make them pass. If a test fails, fix the code, not the assertion.
- Keep `flutter analyze` at 0 issues for both apps after every task.
- Do not touch files outside the paths each task lists. In particular: do NOT modify `skills-lock.json`, `memory-bank/`, `.claude/`, or `docs/` (except nothing — this plan is already written).
- All user-visible strings in admin/mobile screens are Arabic (RTL) — this is the app convention.
- The repo's `Either<Failure, T>` seam (`core/result.dart`) is the error contract for repositories; screens fold it and render `f.message` (Arabic) — never `throw` inside `setState`.

## Verification gates (run after each task; full set at the end)

```powershell
# Admin app
cd apps\admin; flutter analyze; flutter test

# Mobile app
cd apps\mobile; flutter analyze; flutter test

# Edge functions (unchanged expected, but confirm no collateral damage)
deno test --allow-env --allow-net supabase/functions/

# Diagnostic engine (only after FUP-03)
deno check diagnostic_engine/engine.ts diagnostic_engine/engine_test.ts
```

---

## FUP-01 — Delete dead admin auth/home screens and their dead tests

**Context**: `apps/admin/lib/screens/home_screen.dart`, `apps/admin/lib/features/auth/login_screen.dart`, and `apps/admin/lib/features/auth/otp_screen.dart` are pre-router leftovers. The live admin app is routed by `apps/admin/lib/app_router.dart` (`/login` → `AdminLoginScreen` in `features/auth/admin_login_screen.dart`). Grep confirms the three dead files are referenced only by their own test files.

**Edits**:

1. Delete these files:
   - `apps/admin/lib/screens/home_screen.dart` (delete the `screens/` directory if it becomes empty)
   - `apps/admin/lib/features/auth/login_screen.dart`
   - `apps/admin/lib/features/auth/otp_screen.dart`
   - `apps/admin/test/features/auth/login_screen_test.dart`
   - `apps/admin/test/features/auth/otp_screen_test.dart`

2. Rewrite `apps/admin/test/widget_test.dart` — it currently imports the dead `package:admin/screens/home_screen.dart`. Replace with a smoke test of the real login screen:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/features/auth/admin_login_screen.dart';

void main() {
  testWidgets('admin login screen smoke renders', (tester) async {
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(home: AdminLoginScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.text('تسجيل دخول المشرفين'), findsOneWidget);
    expect(find.text('رقم الهاتف'), findsOneWidget);
  });
}
```

(If `AdminLoginScreen` requires overrides to construct its `adminAuthProvider` without Supabase initialized, inspect `apps/admin/lib/core/auth/admin_auth_provider.dart` and the existing `test/features/auth/admin_auth_test.dart` for the established pattern — reuse it. The screen's `build` renders the phone field immediately, so no auth call should fire before the assertion.)

3. Sweep for stragglers: `grep -r "screens/home_screen\|features/auth/login_screen\|features/auth/otp_screen" apps/admin/lib apps/admin/test` must return zero Dart import hits (admin's own `admin_login_screen.dart` is a different file — do not confuse).

**Verify**: `cd apps\admin; flutter analyze` (0 issues) then `flutter test` (all pass, count drops by the 2 deleted suites).

---

## FUP-02 — Dedupe `_BackgroundDecorations` / `_FooterLinks` (mobile auth)

**Context**: `apps/mobile/lib/features/auth/login_screen.dart` (classes at lines 125 and 357) and `apps/mobile/lib/features/auth/otp_screen.dart` (lines 160 and 406) carry near-identical private widgets. `_FooterLinks` is byte-identical. `_BackgroundDecorations` differs only in root widget: `Positioned.fill` (login) vs `SizedBox.expand` (otp) — both call sites are direct children of a `Stack`, so a single `Positioned.fill` version serves both.

**Edits**:

1. Create `apps/mobile/lib/core/auth/widgets/auth_shared_widgets.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:mobile/services/app_strings.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/app_typography.dart';

class AuthBackgroundDecorations extends StatelessWidget {
  const AuthBackgroundDecorations({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 500,
                height: 500,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.secondaryContainer.withValues(alpha: 0.2),
                ),
              ),
            ),
            Positioned(
              bottom: -150,
              left: -150,
              child: Container(
                width: 600,
                height: 600,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.tertiaryFixed.withValues(alpha: 0.1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthFooterLinks extends StatelessWidget {
  const AuthFooterLinks({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        Text(
          AppStrings.privacyPolicy,
          style: AppTypography.labelMd.copyWith(
            color: AppColors.inversePrimary,
          ),
        ),
        Text(
          AppStrings.termsConditions,
          style: AppTypography.labelMd.copyWith(
            color: AppColors.inversePrimary,
          ),
        ),
        Text(
          AppStrings.support,
          style: AppTypography.labelMd.copyWith(
            color: AppColors.inversePrimary,
          ),
        ),
      ],
    );
  }
}
```

2. In both `login_screen.dart` and `otp_screen.dart`:
   - Add `import 'package:mobile/core/auth/widgets/auth_shared_widgets.dart';`
   - Replace usages `const _BackgroundDecorations()` → `const AuthBackgroundDecorations()` and `const _FooterLinks()` → `const AuthFooterLinks()`
   - Delete the two private class bodies from each file.
   - Remove now-unused imports only if the analyzer flags them (`AppStrings`/`AppTypography` may still be used elsewhere in each screen — let the analyzer decide, then clean).

**Verify**: `cd apps\mobile; flutter analyze` (0 issues) then `flutter test` (94/94 expected — no test counts change; widget tests assert rendered output, not class names).

---

## FUP-03 — Purge dead diagnostic-engine files

**Context**: `diagnostic_engine/` has two parallel engine implementations and several "real" verification runners that import edge functions deleted by migration 0070 (Paymob decommission). Verified dead (zero code references outside docs/memory-bank):

- `deno_engine.ts` — the Deno engine duplicate. `package.json` main/audit point at `engine.ts`; `engine_test.ts` imports `./engine.ts`.
- `test_real_reconcile_payments.ts` — imports `../supabase/functions/reconcile-payments/index.ts` (deleted).
- `test_real_payment_flow.ts` — imports `paymob-checkout/index.ts` and `paymob-webhook/index.ts` (deleted).
- `test_real_all_features.ts` — imports both dead runners above.

**Edits**: Delete those 4 files. Nothing else in the repo references them (`grep -r "test_real_all_features\|test_real_payment_flow\|test_real_reconcile_payments\|deno_engine" --include="*.ts" --include="*.json" .` excluding node_modules must return only docs/memory-bank prose hits, which we do not edit).

**Verify**:
```powershell
deno check diagnostic_engine/engine.ts diagnostic_engine/engine_test.ts
node --check diagnostic_engine/engine_test.ts 2>$null; echo "exit=$LASTEXITCODE"   # informational only
deno test --allow-env --allow-net diagnostic_engine/engine_test.ts
```
The engine_test suite (5 tests) must pass. Also `npm run --prefix diagnostic_engine audit` must NOT be executed (it needs live credentials — do not run it).

---

## FUP-04 — Analytics screens: Arabic strings, real error handling, drop no-op export buttons

**Context**: The three analytics screens (`apps/admin/lib/features/analytics/payments_screen.dart`, `bookings_screen.dart`, `utilization_screen.dart`) have three defects each: (1) `res.fold((f) => throw f, ...)` inside `setState` — a repository `Failure` crashes the widget; (2) the `catch` swallows the error and the screen then shows the empty state, lying to the admin; (3) all user-visible strings are English and the payments/bookings app bars carry a no-op `Export CSV` button (the working export lives in `AnalyticsAdminScreen`'s `ExportReportButton`). Post-migration-0083, `v_analytics_payments` money columns (`total_paid`, `total_refunded`) are integer piastres — format with `formatEgp` from `apps/admin/lib/core/money_format.dart`.

**Edits** (apply the same pattern to all three screens):

1. State fields: `bool _loading = true; List<Map<String, dynamic>> _data = []; String? _error;`

2. `_loadData` — no try/catch, no throw (the repository already returns `Either`):

```dart
Future<void> _loadData() async {
  final res = await widget.repo.paymentRows(); // bookingRows / utilizationRows
  if (!mounted) return;
  setState(() {
    _loading = false;
    res.fold((f) => _error = f.message, (rows) => _data = rows);
  });
}
```

3. Build: error branch before empty branch:

```dart
body: _loading
    ? const Center(child: CircularProgressIndicator())
    : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          )
        : _data.isEmpty
            ? const Center(child: Text('لا توجد بيانات بعد'))
            : ListView.builder(...)
```

4. Localize:
   - `PaymentsScreen` AppBar: `'تحليلات المدفوعات'`; rows: `title: Text('الشهر: ${item['month']}')`, `subtitle: Text('مدفوع: ${formatEgp((item['total_paid'] as num?)?.toInt() ?? 0)} | مسترد: ${formatEgp((item['total_refunded'] as num?)?.toInt() ?? 0)}')`, `trailing: Text('عدد العمليات: ${item['count_paid']}')`
   - `BookingsScreen` AppBar: `'تحليلات الحجوزات'`; rows: `subtitle: Text('الشهر: ${item['month']}')`, `trailing: Text('إجمالي الحجوزات: ${item['bookings_total']}')`
   - `UtilizationScreen` AppBar: `'نسبة استخدام المواعيد'`; rows: `subtitle: Text('الشهر: ${item['month']}')`, `trailing: Text('نسبة الاستخدام: ${item['utilization_pct']}%')`
   - Payments screen: `import '../../core/money_format.dart';`

5. Delete the `actions: [TextButton.icon(... Export CSV ...)]` block from the payments and bookings AppBars (the button's `onPressed` is `() {}` — dead UI).

6. Update `apps/admin/test/analytics_screens_test.dart` — assert the Arabic titles instead of the English ones. Also add a failure-path test: inspect `apps/admin/test/helpers/mock_supabase.dart`; if it supports forcing an error on `.from(view).select()`, add one test asserting the payments screen renders the Arabic failure message instead of crashing. If the helper cannot express failure cleanly, extend the helper minimally (e.g. a `MockSupabase.failing()` constructor) rather than skipping the test.

**Verify**: `cd apps\admin; flutter analyze; flutter test` — analytics tests pass with Arabic assertions; no test deleted.

---

## FUP-05 — `ExportReportButton` goes through the repository seam

**Context**: `apps/admin/lib/features/analytics/export_report_button.dart` holds `final dynamic client;` and calls `widget.client!.functions.invoke('analytics-export', ...)` directly — bypassing `AnalyticsRepository` (the typed seam), leaking raw exception text (`'فشل تصدير التقرير: $e'`) into a SnackBar, and its non-web path silently does nothing with the CSV. `AnalyticsAdminScreen` passes its `SupabaseClient? client` straight through.

**Edits**:

1. `apps/admin/lib/features/analytics/analytics_repository.dart` — add the export method (keep existing methods untouched):

```dart
import 'package:supabase_flutter/supabase_flutter.dart' show HttpMethod;
// (merge into the existing supabase_flutter import)

  Future<Either<Failure, String>> exportPaymentsCsv() async {
    try {
      final res = await _db.functions.invoke(
        'analytics-export',
        method: HttpMethod.get,
        queryParameters: const {'report': 'payments'},
      );
      if (res.status != 200) {
        return Left(Failure('فشل تصدير التقرير (رمز ${res.status})'));
      }
      return Right(res.data?.toString() ?? '');
    } catch (_) {
      return Left(Failure('فشل تصدير التقرير'));
    }
  }
```

(Check `Failure` in `core/result.dart` for its exact constructor shape — `Failure.from(e)` exists; if the plain positional constructor differs, adapt to whatever it exposes, keeping the Arabic message.)

2. `export_report_button.dart`:
   - Replace `final dynamic client;` with `final AnalyticsRepository? repository;` (import `analytics_repository.dart`; drop the now-unneeded `supabase_flutter` import if nothing else uses it).
   - `_handleExport`:

```dart
Future<void> _handleExport() async {
  setState(() => _loading = true);
  final res = widget.onExport != null
      ? await _runCustom()
      : await repository!.exportPaymentsCsv();
  ...
}
```
   Concretely: when `onExport` is set, run it and treat thrown exceptions as failure with message `'فشل تصدير التقرير'` (no raw `$e`). Otherwise (repository must then be non-null; if both are null, show the same Arabic failure message instead of throwing `Exception('No client or export handler provided')`). Fold the `Either`: `Left(f)` → red SnackBar `f.message`; `Right(csv)` → `downloadCsvOnWeb(csv, 'analytics.csv')` when `kIsWeb && csv.isNotEmpty`, then the existing green `'تم تصدير التقرير بنجاح'` SnackBar. Keep the `finally` reset of `_loading`.

3. `apps/admin/lib/features/analytics/analytics_admin_screen.dart`: `ExportReportButton(client: client)` → `ExportReportButton(repository: client == null ? null : AnalyticsRepository(client!))` (import the repository).

**Verify**: `cd apps\admin; flutter analyze; flutter test`. No existing tests reference `ExportReportButton`'s `client` param (verified: only attendance/revenue chart tests exist under `test/features/analytics/`).

---

## FUP-06 — Extract the certificate verification bottom sheet (mobile)

**Context**: `_openVerificationDialog()` in `apps/mobile/lib/features/family_archive/family_certificates_screen.dart` (lines 46–248, ~202 lines) builds an entire stateful modal inline with `StatefulBuilder` and hand-rolled local mutable captures. Extract it into its own `StatefulWidget`.

**Edits**:

1. Create `apps/mobile/lib/features/family_archive/certificate_verification_sheet.dart` — public `CertificateVerificationSheet` StatefulWidget:

```dart
import 'package:flutter/material.dart';

import 'sacramental_models.dart';
import 'sacramental_repository.dart';

class CertificateVerificationSheet extends StatefulWidget {
  const CertificateVerificationSheet({super.key, required this.repository});

  final SacramentalRecordsRepository repository;

  @override
  State<CertificateVerificationSheet> createState() =>
      _CertificateVerificationSheetState();
}
```

The state class owns `tokenController` (dispose it in `dispose()`), `isVerifying`, `verifyError`, `verificationResult`. Its `build` returns the exact `Padding → SingleChildScrollView → Column` tree currently produced by the `StatefulBuilder` (lines 61–243), with `setModalState` → plain `setState`, and the verify button calling `widget.repository.verifyCertificate(token)` exactly as today. Move the widget verbatim — no visual or behavioral changes.

2. `family_certificates_screen.dart` — `_openVerificationDialog` becomes:

```dart
void _openVerificationDialog() {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => CertificateVerificationSheet(repository: widget.repository),
  );
}
```

(If `sacramental_models.dart`'s `CertificateVerificationResult` was only used by the dialog in the screen file, move that import to the new file and drop it from the screen.)

**Verify**: `cd apps\mobile; flutter analyze; flutter test` — `test/features/family_archive/family_archive_test.dart` must pass unchanged (it drives the screen through a fake repository; the extraction keeps the same UI tree and repository calls).

---

## FUP-07 — Decompose `AllocationMatrixCalendarScreen.build()`

**Context**: `apps/admin/lib/features/allocation/allocation_matrix_screen.dart` — `build()` spans lines 138–435 (~297 lines): an inline "controls" Card (date navigator + venue/priest dropdowns), the allocation grid (already extracted as `_buildAllocationGrid()` at line 437), and the unassigned-bookings sidebar. Extract the two inline blocks into private widgets. This is a pure structural refactor — zero behavior change.

**Edits**:

1. `_AllocationControlsCard` — private StatelessWidget (or StatefulWidget if it needs `setState` for its own dropdown state; prefer keeping state in the parent and passing values + `onChanged` callbacks). Constructor takes: the selected date / navigation callbacks (`onPreviousDay`/`onNextDay` or a `ValueChanged<DateTime>`), selected venue id + list + `onVenueChanged`, selected priest id + list + `onPriestChanged`, and the loading flag if it gates the dropdowns. Body = the existing controls Card verbatim.

2. `_UnassignedBookingsPanel` — private StatelessWidget. Constructor takes the unassigned `List<EventBookingAdminItem>` and the `onAssign` callback (opening `AssignPriestVenueDialog`). Body = the existing sidebar verbatim (keep `_statusColor`/`_statusLabelAr` helpers where they are; pass labels in or keep them accessible).

3. `build()` reduces to: Scaffold → loading/error branches (unchanged) → controls card widget → allocation grid → sidebar widget. Rename nothing public. `allocation_matrix_test.dart` drives the screen via its public API and must pass **unchanged**.

**Verify**: `cd apps\admin; flutter analyze; flutter test` — allocation matrix tests pass with no edits to the test file.

---

## FUP-08 — Housekeeping (orchestrator-owned, already done)

`opencode.json` contains a live API key and stays local: added to `.gitignore` on 2026-09-05 (this edit is NOT part of the agy dispatch). `.agy-briefs/` is already gitignored.

---

## Final acceptance checklist (run by implementer, re-run by orchestrator)

- [ ] `cd apps\admin; flutter analyze` → 0 issues
- [ ] `cd apps\admin; flutter test` → all pass
- [ ] `cd apps\mobile; flutter analyze` → 0 issues
- [ ] `cd apps\mobile; flutter test` → all pass
- [ ] `deno test --allow-env --allow-net supabase/functions/` → 75/75
- [ ] `deno check diagnostic_engine/engine.ts diagnostic_engine/engine_test.ts` → clean
- [ ] `deno test --allow-env --allow-net diagnostic_engine/engine_test.ts` → 5/5
- [ ] Grep sweeps: no references to deleted files (`home_screen`, dead `login_screen`/`otp_screen` admin variants, `deno_engine`, dead `test_real_*` runners) anywhere in `apps/` or `diagnostic_engine/`
- [ ] `git status` shows only files listed in this plan (+ the two deleted-file sets)
- [ ] No changes to `supabase/`, `skills-lock.json`, `memory-bank/`
