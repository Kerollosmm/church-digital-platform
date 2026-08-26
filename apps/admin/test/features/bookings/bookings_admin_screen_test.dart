import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/bookings/bookings_admin_screen.dart';
import 'package:admin/features/bookings/bookings_provider.dart';

class FakeBookingsGateway implements BookingsGateway {
  FakeBookingsGateway(this.bookings);

  final List<Map<String, dynamic>> bookings;
  final List<String> rpcCalls = [];
  void Function()? _onChange;

  @override
  Future<List<Map<String, dynamic>>> loadBookings({String? status}) async {
    return status == null
        ? [...bookings]
        : bookings.where((b) => b['status'] == status).toList();
  }

  @override
  Future<void> confirmBooking(int bookingId) async {
    rpcCalls.add('confirm_booking');
  }

  @override
  Future<void> completeBooking(int bookingId) async {
    rpcCalls.add('complete_booking');
  }

  @override
  Future<void> cancelBooking(int bookingId) async {
    rpcCalls.add('cancel_booking');
  }

  @override
  void Function() subscribeChanges(void Function() onChange) {
    _onChange = onChange;
    return () {};
  }

  // Test hook mirroring a realtime postgres change on [table].
  void triggerChange(String table) {
    _onChange?.call();
  }
}

void main() {
  testWidgets('bookings admin filters by status and confirms a booking', (
    tester,
  ) async {
    final gateway = FakeBookingsGateway([
      {
        'id': 1,
        'slot_id': 1,
        'status': 'AWAITING_CALL',
        'user_id': 'u1',
        'paid_amount': 50,
      },
      {
        'id': 2,
        'slot_id': 2,
        'status': 'CONFIRMED',
        'user_id': 'u2',
        'paid_amount': 50,
      },
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: BookingsAdminScreen(gateway: gateway)),
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
    expect(gateway.rpcCalls.last, 'confirm_booking');
  });

  testWidgets(
    'bookings_provider reloads state when gateway signals changes for bookings and service_slots',
    (tester) async {
      final gateway = FakeBookingsGateway([
        {
          'id': 1,
          'slot_id': 1,
          'status': 'AWAITING_CALL',
          'user_id': 'u1',
          'paid_amount': 50,
        },
      ]);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: BookingsAdminScreen(gateway: gateway)),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('حجز #1 — AWAITING_CALL'), findsOneWidget);

      // Realtime-equivalent: new booking row arrives via bookings table change
      gateway.bookings.add({
        'id': 3,
        'slot_id': 1,
        'status': 'PENDING_PAYMENT',
        'user_id': 'u3',
        'paid_amount': 100,
      });
      gateway.triggerChange('bookings');

      await tester.pump();
      await tester.pump();
      expect(find.text('حجز #3 — PENDING_PAYMENT'), findsOneWidget);

      // And via service_slots change
      gateway.bookings.add({
        'id': 4,
        'slot_id': 2,
        'status': 'CONFIRMED',
        'user_id': 'u4',
        'paid_amount': 75,
      });
      gateway.triggerChange('service_slots');

      await tester.pump();
      await tester.pump();
      expect(find.text('حجز #4 — CONFIRMED'), findsOneWidget);
    },
  );
}
