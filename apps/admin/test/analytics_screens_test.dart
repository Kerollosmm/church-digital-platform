import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin/features/analytics/utilization_screen.dart';
import 'package:admin/features/analytics/payments_screen.dart';
import 'package:admin/features/analytics/bookings_screen.dart';
import 'package:admin/features/analytics/analytics_repository.dart';
import 'helpers/mock_supabase.dart';
import 'helpers/fake_supabase.dart';

void main() {
  final repo = AnalyticsRepository(MockSupabase().build());

  testWidgets('utilization screen renders title', (tester) async {
    await tester.pumpWidget(MaterialApp(home: UtilizationScreen(repo: repo)));
    expect(find.text('نسبة استخدام المواعيد'), findsOneWidget);
  });

  testWidgets('payments screen renders title', (tester) async {
    await tester.pumpWidget(MaterialApp(home: PaymentsScreen(repo: repo)));
    expect(find.text('تحليلات المدفوعات'), findsOneWidget);
  });

  testWidgets('bookings screen renders title', (tester) async {
    await tester.pumpWidget(MaterialApp(home: BookingsScreen(repo: repo)));
    expect(find.text('تحليلات الحجوزات'), findsOneWidget);
  });

  testWidgets('payments screen renders error message on failure', (tester) async {
    final failingRepo = AnalyticsRepository(MockSupabase.failing().build());
    await tester.pumpWidget(MaterialApp(home: PaymentsScreen(repo: failingRepo)));
    await tester.pumpAndSettle();
    expect(find.text('فشل الاتصال بالخادم'), findsOneWidget);
  });

  test('AnalyticsRepository.exportPaymentsCsv returns Right on success', () async {
    final fakeDb = FakeSupabase({});
    final repo = AnalyticsRepository(fakeDb);
    final res = await repo.exportPaymentsCsv();
    expect(res.isRight, isTrue);
    expect(fakeDb.functions.invokedFunctions, contains('analytics-export'));
    expect(fakeDb.functions.lastMethod, HttpMethod.get);
    expect(fakeDb.functions.lastQueryParameters, {'report': 'payments'});
  });

  test('AnalyticsRepository.exportPaymentsCsv returns Left on exception', () async {
    final repo = AnalyticsRepository(Object());
    final res = await repo.exportPaymentsCsv();
    expect(res.isLeft, isTrue);
    expect(res.leftOrNull?.message, 'فشل تصدير التقرير');
  });
}
