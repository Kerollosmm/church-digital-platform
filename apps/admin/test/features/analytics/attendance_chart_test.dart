import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:admin/features/analytics/attendance_chart_widget.dart';
import '../../helpers/fake_supabase.dart';

void main() {
  testWidgets(
    'AttendanceChartWidget queries v_analytics_utilization and renders BarChart with legend and Arabic labels',
    (tester) async {
      final fakeDb = FakeSupabase({
        'v_analytics_utilization': [
          {'title_ar': 'قداس الأحد', 'slots_total': 100, 'slots_booked': 85},
          {'title_ar': 'قداس الجمعة', 'slots_total': 120, 'slots_booked': 90},
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttendanceChartWidget(
              fetchData: () async => List<Map<String, dynamic>>.from(
                await fakeDb.from('v_analytics_utilization').select(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      // Verify BarChart widget renders
      expect(find.byType(BarChart), findsOneWidget);

      // Verify Arabic Legend items render
      expect(find.text('السعة الكلية'), findsOneWidget);
      expect(find.text('الحضور الفعلي'), findsOneWidget);

      // Verify Arabic service title labels render
      expect(find.text('قداس الأحد'), findsOneWidget);
      expect(find.text('قداس الجمعة'), findsOneWidget);
    },
  );

  testWidgets(
    'AttendanceChartWidget renders empty message when v_analytics_utilization returns no rows',
    (tester) async {
      final fakeDb = FakeSupabase({'v_analytics_utilization': []});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttendanceChartWidget(
              fetchData: () async => List<Map<String, dynamic>>.from(
                await fakeDb.from('v_analytics_utilization').select(),
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

  testWidgets(
    'AttendanceChartWidget surfaces friendly error message on fetch failure',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttendanceChartWidget(
              fetchData: () async {
                throw Exception('Database query error');
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('حدث خطأ أثناء تحميل البيانات'), findsOneWidget);
    },
  );
}
