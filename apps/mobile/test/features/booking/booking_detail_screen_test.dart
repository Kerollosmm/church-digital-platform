import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/booking/booking_detail_screen.dart';
import 'package:mobile/features/booking/payment_proof_screen.dart';
import 'package:mobile/models/booking.dart';
import 'package:mobile/services/app_strings.dart';
import '../../helpers/fakes.dart';
import '../../helpers/pump_with_router.dart';

void main() {
  testWidgets(
    'BookingDetailScreen renders checkout banner, summary, opt-in and drives confirm booking flow',
    (tester) async {
      final repo = FakeBookingRepository(
        bookings: [
          Booking(
            id: 5,
            status: 'PENDING_PAYMENT',
            serviceName: 'قداس',
            paidAmount: 50,
          ),
        ],
      );

      await pumpWithRouter(
        tester,
        home: BookingDetailScreen(
          slot: const {
            'slot_id': 101,
            'title_ar': 'القداس الأول',
            'starts_at': '2026-08-15T06:00:00+02:00',
            'price': 50,
            'location': 'الكنيسة الكبيرة',
          },
          repository: repo,
        ),
      );

      expect(find.text(AppStrings.completeBookingPrompt), findsOneWidget);
      expect(find.text('القداس الأول'), findsOneWidget);
      expect(find.text('50 ${AppStrings.egp}'), findsOneWidget);
      expect(find.text(AppStrings.whatsappOptIn), findsOneWidget);
      expect(find.text(AppStrings.confirmBooking), findsOneWidget);

      await tester.tap(find.text(AppStrings.whatsappOptIn));
      await tester.tap(
        find.widgetWithText(FilledButton, AppStrings.confirmBooking),
      );
      await tester.pumpAndSettle();

      expect(repo.calls, contains('reserveAndPay'));
      expect(find.byType(PaymentProofScreen), findsOneWidget);
    },
  );
}
