import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/bookings/manual_book_repository.dart';
import 'package:admin/features/bookings/manual_book_screen.dart';
import '../../helpers/mock_supabase.dart';

void main() {
  testWidgets(
    'ManualBookScreen renders form inputs and calls manual_book RPC on submit',
    (tester) async {
      final mock = MockSupabase(
        tables: {
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
        },
        rpc: {
          'manual_book': (args) async {
            // capture asserted below via requestLog
            return null;
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ManualBookScreen(repo: ManualBookRepository(mock.build())),
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

      await tester.enterText(
        find.byKey(const Key('phone_field')),
        '01234567890',
      );

      await tester.tap(find.byKey(const Key('opt_in_checkbox')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('notes_field')),
        'حجز يدوي من الخدمة',
      );

      await tester.tap(find.byKey(const Key('submit_button')));
      await tester.pumpAndSettle();

      final rpcCall = mock.requestLog.singleWhere(
        (p) => p.endsWith('/rpc/manual_book'),
      );
      expect(rpcCall, isNotNull);
    },
  );
}
