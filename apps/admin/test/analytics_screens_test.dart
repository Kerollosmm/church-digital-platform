import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/analytics/utilization_screen.dart';
import 'package:admin/features/analytics/payments_screen.dart';
import 'package:admin/features/analytics/bookings_screen.dart';
import 'helpers/fake_supabase.dart';

void main() {
  final fake = FakeSupabase({});
  final supabase = fake as dynamic;

  testWidgets('utilization screen renders title', (tester) async {
    await tester.pumpWidget(MaterialApp(home: UtilizationScreen(supabase: supabase)));
    expect(find.text('Slot utilization'), findsOneWidget);
  });

  testWidgets('payments screen renders title', (tester) async {
    await tester.pumpWidget(MaterialApp(home: PaymentsScreen(supabase: supabase)));
    expect(find.text('Payments Analytics'), findsOneWidget);
  });

  testWidgets('bookings screen renders title', (tester) async {
    await tester.pumpWidget(MaterialApp(home: BookingsScreen(supabase: supabase)));
    expect(find.text('Bookings Analytics'), findsOneWidget);
  });
}
