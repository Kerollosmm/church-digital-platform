import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/phone_verify_gate.dart';
import 'package:mobile/features/booking/booking_detail_screen.dart';
import 'package:mobile/features/booking/slot_grid_screen.dart';
import 'package:mobile/services/app_strings.dart';
import '../../helpers/fakes.dart';
import '../../helpers/mock_auth_gateway.dart';
import '../../helpers/pump_with_router.dart';

void main() {
  testWidgets(
    'SlotGridScreen -> BookingDetailScreen triggers inline PhoneVerifyGate modal when logged out, verifies OTP, and confirms booking',
    (tester) async {
      final mockGateway = MockAuthGateway();
      final repo = FakeBookingRepository(
        slots: [
          {
            'slot_id': 101,
            'service_id': 1,
            'title_ar': 'قداس الجمعة - هيكل مارجرجس',
            'starts_at': '2026-08-15T06:00:00+02:00',
            'available_seats': 50,
            'slot_status': 'AVAILABLE',
            'price': 0,
            'location': 'الكنيسة الكبرى',
          },
        ],
        bookings: [fakeBooking],
      );

      await pumpWithRouter(
        tester,
        home: SlotGridScreen(
          serviceId: 1,
          repository: repo,
          gateway: mockGateway,
          isLoggedIn: () => mockGateway.isAuthenticated,
        ),
      );

      // 1. Verify slot is listed and tap to open BookingDetailScreen
      expect(find.text('قداس الجمعة - هيكل مارجرجس'), findsOneWidget);
      await tester.tap(find.text('قداس الجمعة - هيكل مارجرجس'));
      await tester.pumpAndSettle();

      expect(find.byType(BookingDetailScreen), findsOneWidget);

      // 2. Tap Confirm Booking while unauthenticated -> Phone modal appears
      await tester.tap(
        find.widgetWithText(FilledButton, AppStrings.confirmBooking),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PhoneVerifyForm), findsOneWidget);
      expect(mockGateway.isAuthenticated, isFalse);

      // 3. Enter Egyptian phone number and request OTP
      await tester.enterText(find.byType(TextFormField), '01012345678');
      await tester.tap(find.text(AppStrings.sendOtpCta));
      await tester.pumpAndSettle();

      // 4. Enter test OTP 123456
      final otpFields = find.byType(TextField);
      expect(otpFields, findsNWidgets(6));
      for (int i = 0; i < 6; i++) {
        await tester.enterText(otpFields.at(i), '${i + 1}');
      }
      await tester.pumpAndSettle();

      // 5. User is now authenticated and booking execution completes
      expect(mockGateway.isAuthenticated, isTrue);
      expect(repo.calls, contains('reserveAndPay'));
    },
  );
}
