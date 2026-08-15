import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/bookings/bookings_admin_screen.dart';
import '../../helpers/fake_supabase.dart';

void main() {
  testWidgets('bookings admin filters by status and confirms a booking', (tester) async {
    final fake = FakeSupabase({
      'bookings': [
        {'id': 1, 'slot_id': 1, 'status': 'AWAITING_CALL', 'user_id': 'u1', 'paid_amount': 50},
        {'id': 2, 'slot_id': 2, 'status': 'CONFIRMED', 'user_id': 'u2', 'paid_amount': 50},
      ],
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: BookingsAdminScreen(db: fake)),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('حجز #1 — AWAITING_CALL'), findsOneWidget);
    expect(find.text('حجز #2 — CONFIRMED'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'AWAITING_CALL'));
    await tester.pump();
    await tester.pump();
    expect(find.text('حجز #2 — CONFIRMED'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'الكل'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pump();
    await tester.pump();
    expect(fake.rpcCalls.last, contains('confirm_booking'));
  });

  testWidgets('bookings_provider subscribes to postgres_changes for bookings and service_slots and updates UI state on payload', (tester) async {
    final fake = FakeSupabase({
      'bookings': [
        {'id': 1, 'slot_id': 1, 'status': 'AWAITING_CALL', 'user_id': 'u1', 'paid_amount': 50},
      ],
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: BookingsAdminScreen(db: fake)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('حجز #1 — AWAITING_CALL'), findsOneWidget);

    // Verify channel created and subscribed to bookings and service_slots
    expect(fake.channels.isNotEmpty, isTrue);
    final channel = fake.channels.first;
    expect(channel.isSubscribed, isTrue);

    final tables = channel.postgresChangeListeners.map((l) => l['table']).toList();
    expect(tables, contains('bookings'));
    expect(tables, contains('service_slots'));

    // Update fake data and trigger realtime change on bookings
    fake.data['bookings']!.add({
      'id': 3,
      'slot_id': 1,
      'status': 'PENDING_PAYMENT',
      'user_id': 'u3',
      'paid_amount': 100,
    });
    channel.triggerPostgresChange('bookings');

    await tester.pump();
    await tester.pump();
    expect(find.text('حجز #3 — PENDING_PAYMENT'), findsOneWidget);

    // Trigger realtime change on service_slots
    fake.data['bookings']!.add({
      'id': 4,
      'slot_id': 2,
      'status': 'CONFIRMED',
      'user_id': 'u4',
      'paid_amount': 75,
    });
    channel.triggerPostgresChange('service_slots');

    await tester.pump();
    await tester.pump();
    expect(find.text('حجز #4 — CONFIRMED'), findsOneWidget);
  });
}
