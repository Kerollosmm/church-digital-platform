import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/slots/slots_admin_repository.dart';
import 'package:admin/features/slots/slots_admin_screen.dart';
import '../../helpers/mock_supabase.dart';

void main() {
  testWidgets('slots admin lists slots and closes one', (tester) async {
    final mock = MockSupabase(tables: {
      'service_slots': [
        {'id': 1, 'service_id': 1, 'starts_at': '2026-08-09T08:00:00+02:00', 'ends_at': '2026-08-09T09:00:00+02:00', 'capacity': 10, 'price': 50, 'status': 'OPEN'}
      ],
    });
    await tester.pumpWidget(MaterialApp(
        home: SlotsAdminScreen(repo: SlotsAdminRepository(mock.build()))));
    await tester.pumpAndSettle();
    expect(find.textContaining('50'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.lock_outline));
    await tester.pumpAndSettle();
    expect(mock.data['service_slots']![0]['status'], 'CLOSED');
  });
}
