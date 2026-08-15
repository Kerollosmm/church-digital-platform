import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_gateway.dart';
import 'package:mobile/core/auth/phone_verify_gate.dart';
import 'package:mobile/features/booking/my_bookings_screen.dart';
import 'package:mobile/models/booking.dart';
import 'package:mobile/services/app_strings.dart';
import '../../helpers/fakes.dart';
import '../../helpers/mock_auth_gateway.dart';


void main() {
  testWidgets(
    'MyBookingsScreen renders PhoneVerifyForm when logged out, verifies OTP, and loads bookings',
    (tester) async {
      final mockGateway = MockAuthGateway();
      final repo = FakeBookingRepository(
        bookings: [
          Booking(
            id: 99,
            status: 'CONFIRMED',
            serviceName: 'قداس القديسة دميانة',
            paidAmount: 0,
            createdAt: DateTime.parse('2026-08-14T07:00:00Z'),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MyBookingsScreen(
            repository: repo,
            gateway: mockGateway,
            isLoggedIn: () => mockGateway.isAuthenticated,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Unauthenticated -> Phone login form is displayed
      expect(find.byType(PhoneVerifyForm), findsOneWidget);
      expect(find.text('${AppStrings.bookingNumberPrefix}99'), findsNothing);

      // 2. Enter Egyptian phone number and send OTP
      await tester.enterText(find.byType(TextFormField), '01011112222');
      await tester.tap(find.text(AppStrings.sendOtpCta));
      await tester.pumpAndSettle();

      // 3. Enter OTP 123456
      final otpFields = find.byType(TextField);
      for (int i = 0; i < 6; i++) {
        await tester.enterText(otpFields.at(i), '${i + 1}');
      }
      await tester.pumpAndSettle();

      // 4. Verification passed -> Authenticated bookings list is displayed
      expect(mockGateway.isAuthenticated, isTrue);
      expect(find.text('${AppStrings.bookingNumberPrefix}99'), findsOneWidget);
    },
  );
}
