import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/booking/booking_ticket_screen.dart';
import 'package:mobile/features/booking/services_list_screen.dart';
import 'package:mobile/services/app_strings.dart';
import '../../helpers/fakes.dart';

void main() {
  final testBooking = <String, dynamic>{
    'id': 123,
    'status': 'CONFIRMED',
    'service_name': 'قداس الأحد',
    'paid_amount': 150,
    'created_at': '2026-10-15T08:00:00',
  };

  testWidgets(
    'BookingTicketScreen renders success header, booking id, status chip, service name, paid amount, and QR placeholder',
    (tester) async {
      final repo = FakeBookingRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: BookingTicketScreen(booking: testBooking, repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.bookingConfirmedSuccess), findsWidgets);
      expect(find.textContaining('123'), findsWidgets);
      expect(find.text('مؤكد'), findsOneWidget);
      expect(find.text('قداس الأحد'), findsWidgets);
      expect(find.textContaining('150'), findsOneWidget);
      expect(find.byType(BookingQrView), findsOneWidget);
      expect(find.text(AppStrings.showQrNotice), findsOneWidget);

    },
  );

  testWidgets('إلغاء calls repository.cancelBooking and pops screen', (
    tester,
  ) async {
    final repo = FakeBookingRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookingTicketScreen(
                      booking: testBooking,
                      repository: repo,
                    ),
                  ),
                );
              },
              child: const Text('Open Ticket'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Ticket'));
    await tester.pumpAndSettle();

    expect(find.byType(BookingTicketScreen), findsOneWidget);

    final cancelFinder = find.text(AppStrings.cancelBooking);
    await tester.ensureVisible(cancelFinder);
    await tester.tap(cancelFinder);
    await tester.pumpAndSettle();

    expect(repo.calls, contains('cancelBooking'));
    expect(find.byType(BookingTicketScreen), findsNothing);
  });

  testWidgets('تعديل navigates to ServicesListScreen', (tester) async {
    final repo = FakeBookingRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: BookingTicketScreen(booking: testBooking, repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    final editFinder = find.text(AppStrings.editBooking);
    await tester.ensureVisible(editFinder);
    await tester.tap(editFinder);
    await tester.pumpAndSettle();

    expect(find.byType(ServicesListScreen), findsOneWidget);
  });
}
