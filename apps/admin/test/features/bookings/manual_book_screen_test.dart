import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/bookings/manual_book_screen.dart';
import '../../helpers/fake_supabase.dart';

void main() {
  testWidgets('ManualBookScreen renders form inputs and calls manual_book RPC on submit', (tester) async {
    final fake = FakeSupabase({
      'v_available_slots': [
        {
          'slot_id': 101,
          'service_id': 1,
          'title_ar': 'قداس الأحد',
          'starts_at': '2026-08-15T08:00:00Z',
          'ends_at': '2026-08-15T10:00:00Z',
          'capacity': 50,
          'price': 0,
          'available_seats': 10,
          'slot_status': 'AVAILABLE',
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ManualBookScreen(db: fake),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField), findsOneWidget);
    expect(find.byKey(const Key('phone_field')), findsOneWidget);
    expect(find.byKey(const Key('opt_in_checkbox')), findsOneWidget);
    expect(find.byKey(const Key('notes_field')), findsOneWidget);
    expect(find.byKey(const Key('submit_button')), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('قداس الأحد').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('phone_field')), '01234567890');

    await tester.tap(find.byKey(const Key('opt_in_checkbox')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('notes_field')), 'حجز يدوي من الخدمة');

    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pumpAndSettle();

    expect(fake.rpcCalls, contains('manual_book'));
    expect(fake.rpcArgs['manual_book'], {
      'p_slot_id': 101,
      'p_phone': '01234567890',
      'p_opt_in': true,
      'p_notes': 'حجز يدوي من الخدمة',
    });
  });
}
