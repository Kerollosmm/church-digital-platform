import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/booking/booking_ticket_screen.dart';
import 'package:mobile/features/booking/my_bookings_screen.dart';
import 'package:mobile/models/booking.dart';
import 'package:mobile/services/app_strings.dart';
import '../../helpers/fakes.dart';

void main() {
  testWidgets(
    'MyBookingsScreen renders list, uses AppStrings, and tapping opens BookingTicketScreen',
    (tester) async {
      final repo = FakeBookingRepository(
        bookings: [
          Booking(
            id: 42,
            status: 'CONFIRMED',
            serviceName: 'قداس القداس',
            paidAmount: 100,
            createdAt: DateTime.parse('2026-08-09T08:00:00Z'),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(home: MyBookingsScreen(repository: repo)),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.myBookingsTitle), findsOneWidget);
      expect(find.text('${AppStrings.bookingNumberPrefix}42'), findsOneWidget);
      expect(find.text('مؤكد'), findsOneWidget);

      await tester.tap(find.text('${AppStrings.bookingNumberPrefix}42'));
      await tester.pumpAndSettle();

      expect(find.byType(BookingTicketScreen), findsOneWidget);
    },
  );
}
