import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_gateway.dart';
import 'package:mobile/features/auth/otp_screen.dart';
import 'package:mobile/services/app_strings.dart';

class FakeAuthGateway implements AuthGateway {
  bool acceptCode = true;
  String? receivedToken;
  final resendCalls = <String>[];

  @override
  Future<void> sendOtp(String phone) async {
    resendCalls.add(phone);
  }

  @override
  Future<bool> verifyOtp(String phone, String token) async {
    receivedToken = token;
    return acceptCode;
  }

  @override
  Future<void> signOut() async {}

  @override
  bool get isAuthenticated => false;
}

void main() {
  testWidgets('verifies OTP with 6 digit boxes and reports success', (
    tester,
  ) async {
    final gateway = FakeAuthGateway();
    var signedIn = false;
    await tester.pumpWidget(
      MaterialApp(
        home: OtpScreen(
          phone: '01000000002',
          gateway: gateway,
          onVerified: () => signedIn = true,
        ),
      ),
    );

    expect(find.text(AppStrings.otpIntro), findsOneWidget);
    expect(find.text('+20 01000000002'), findsOneWidget);
    expect(find.text(AppStrings.changeNumber), findsOneWidget);
    expect(find.text(AppStrings.resendPrompt), findsOneWidget);
    expect(find.text(AppStrings.privacyPolicy), findsOneWidget);
    expect(find.text(AppStrings.termsConditions), findsOneWidget);
    expect(find.text(AppStrings.support), findsOneWidget);

    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(6));

    await tester.enterText(textFields.at(0), '1');
    await tester.enterText(textFields.at(1), '2');
    await tester.enterText(textFields.at(2), '3');
    await tester.enterText(textFields.at(3), '4');
    await tester.enterText(textFields.at(4), '5');
    await tester.enterText(textFields.at(5), '6');

    await tester.tap(find.text(AppStrings.confirmOtp));
    await tester.pumpAndSettle();

    expect(gateway.receivedToken, '123456');
    expect(signedIn, isTrue);
  });

  testWidgets('shows error for wrong code', (tester) async {
    final gateway = FakeAuthGateway()..acceptCode = false;
    await tester.pumpWidget(
      MaterialApp(
        home: OtpScreen(
          phone: '01000000002',
          gateway: gateway,
          onVerified: () {},
        ),
      ),
    );

    final textFields = find.byType(TextField);
    for (var i = 0; i < 6; i++) {
      await tester.enterText(textFields.at(i), '0');
    }

    await tester.tap(find.text(AppStrings.confirmOtp));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.otpInvalid), findsOneWidget);
  });

  testWidgets('resend OTP triggers gateway.sendOtp', (tester) async {
    final gateway = FakeAuthGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: OtpScreen(
          phone: '01000000002',
          gateway: gateway,
          onVerified: () {},
        ),
      ),
    );

    final resendFinder = find.text(AppStrings.resendOtp);
    await tester.ensureVisible(resendFinder);
    await tester.tap(resendFinder);
    await tester.pumpAndSettle();

    expect(gateway.resendCalls, ['01000000002']);
  });
}
