import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/analytics/utilization_screen.dart';
import 'package:admin/features/analytics/payments_screen.dart';
import 'package:admin/features/analytics/bookings_screen.dart';
import 'package:admin/features/analytics/analytics_repository.dart';
import 'helpers/mock_supabase.dart';

void main() {
  final repo = AnalyticsRepository(MockSupabase().build());

  testWidgets('utilization screen renders title', (tester) async {
    await tester.pumpWidget(MaterialApp(home: UtilizationScreen(repo: repo)));
    expect(find.text('Slot utilization'), findsOneWidget);
  });

  testWidgets('payments screen renders title', (tester) async {
    await tester.pumpWidget(MaterialApp(home: PaymentsScreen(repo: repo)));
    expect(find.text('Payments Analytics'), findsOneWidget);
  });

  testWidgets('bookings screen renders title', (tester) async {
    await tester.pumpWidget(MaterialApp(home: BookingsScreen(repo: repo)));
    expect(find.text('Bookings Analytics'), findsOneWidget);
  });
}
