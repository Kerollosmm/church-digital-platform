import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/bookings/emergency_override_screen.dart';
import '../../helpers/fake_supabase.dart';

void main() {
  testWidgets('EmergencyOverrideScreen renders selectors, refund toggle, and calls emergency_override RPC on submit', (tester) async {
    final fake = FakeSupabase({
      'bookings': [
        {'id': 201, 'slot_id': 50, 'status': 'CONFIRMED', 'user_id': 'u1'},
      ],
      'v_available_slots': [
        {
          'slot_id': 102,
          'service_id': 1,
          'title_ar': 'قداس الجمعة',
          'starts_at': '2026-08-16T08:00:00Z',
          'ends_at': '2026-08-16T10:00:00Z',
          'capacity': 50,
          'price': 0,
          'available_seats': 5,
          'slot_status': 'AVAILABLE',
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: EmergencyOverrideScreen(db: fake),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('booking_id_field')), findsOneWidget);
    expect(find.byType(DropdownButtonFormField), findsOneWidget);
    expect(find.byKey(const Key('refund_toggle')), findsOneWidget);
    expect(find.byKey(const Key('submit_button')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('booking_id_field')), '201');

    await tester.tap(find.byType(DropdownButtonFormField));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('قداس الجمعة').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('refund_toggle')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pumpAndSettle();

    expect(fake.rpcCalls, contains('emergency_override'));
    expect(fake.rpcArgs['emergency_override'], {
      'p_booking_id': 201,
      'p_new_slot_id': 102,
      'p_refund': true,
    });
  });
}
