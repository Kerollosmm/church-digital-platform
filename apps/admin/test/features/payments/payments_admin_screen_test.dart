import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/payments/payments_admin_screen.dart';
import '../../helpers/fake_supabase.dart';

void main() {
  testWidgets('payments admin lists payments with status', (tester) async {
    final fake = FakeSupabase({
      'payments': [
        {'id': 1, 'booking_id': 7, 'amount': 50, 'status': 'PAID', 'gateway_ref': 9001}
      ],
    });
    await tester.pumpWidget(MaterialApp(home: PaymentsAdminScreen(db: fake)));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('PAID'), findsOneWidget);
    expect(find.textContaining('50'), findsOneWidget);
  });
}
