import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin/features/analytics/revenue_chart_widget.dart';
import 'package:admin/features/analytics/export_report_button.dart';
import '../../helpers/fake_supabase.dart';

void main() {
  testWidgets(
    'RevenueChartWidget queries v_analytics_payments and renders PieChart with status breakdown and legend',
    (tester) async {
      final fakeDb = FakeSupabase({
        'v_analytics_payments': [
          {
            'month': '2026-08-01',
            'total_paid': 15000.0,
            'total_refunded': 1200.0,
            'count_paid': 50,
          },
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RevenueChartWidget(
              fetchData: () async => List<Map<String, dynamic>>.from(
                await fakeDb.from('v_analytics_payments').select(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      // Verify PieChart renders
      expect(find.byType(PieChart), findsOneWidget);

      // Verify Arabic Legend items render (paid and refunded)
      expect(find.text('مدفوع'), findsOneWidget);
      expect(find.text('مسترد'), findsOneWidget);
      expect(find.text('قيد الانتظار'), findsNothing);
    },
  );

  testWidgets(
    'RevenueChartWidget renders empty state message when no data available',
    (tester) async {
      final fakeDb = FakeSupabase({'v_analytics_payments': []});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RevenueChartWidget(
              fetchData: () async => List<Map<String, dynamic>>.from(
                await fakeDb.from('v_analytics_payments').select(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('لا توجد بيانات متاحة'), findsOneWidget);
    },
  );

  testWidgets('RevenueChartWidget displays error message on query failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RevenueChartWidget(
            fetchData: () async {
              throw Exception('Database connection failed');
            },
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('حدث خطأ أثناء تحميل البيانات'), findsOneWidget);
  });

  testWidgets(
    'ExportReportButton invokes analytics-export Edge Function with GET method and report parameter',
    (tester) async {
      final fakeDb = FakeSupabase({});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ExportReportButton(client: fakeDb)),
        ),
      );

      await tester.pump();

      final buttonFinder = find.byType(ExportReportButton);
      expect(buttonFinder, findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pump();

      expect(fakeDb.functions.invokedFunctions, contains('analytics-export'));
      expect(fakeDb.functions.lastMethod, HttpMethod.get);
      expect(fakeDb.functions.lastQueryParameters, {'report': 'payments'});
    },
  );
}
