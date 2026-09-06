import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_gateway.dart';
import 'package:mobile/features/auth/login_screen.dart';
import 'package:mobile/services/app_strings.dart';

class FakeAuthGateway implements AuthGateway {
  final otpCalls = <String>[];
  bool sendSucceeds = true;

  @override
  Future<void> sendOtp(String phone) async {
    if (!sendSucceeds) throw Exception('sms-failed');
    otpCalls.add(phone);
  }

  @override
  Future<bool> verifyOtp(String phone, String token) async => true;

  @override
  Future<void> signOut() async {}

  @override
  bool get isAuthenticated => false;
}

void main() {
  testWidgets('renders phone field and sends OTP', (tester) async {
    final gateway = FakeAuthGateway();
    var navigated = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          gateway: gateway,
          onOtpSent: (phone) => navigated = true,
        ),
      ),
    );

    expect(find.text(AppStrings.authTitle), findsOneWidget);
    expect(find.text(AppStrings.authSubtitle), findsOneWidget);
    expect(find.text(AppStrings.phoneLabel), findsOneWidget);
    expect(find.text(AppStrings.privacyPolicy), findsOneWidget);
    expect(find.text(AppStrings.termsConditions), findsOneWidget);
    expect(find.text(AppStrings.support), findsOneWidget);

    await tester.enterText(find.byType(TextField), '01000000002');
    await tester.tap(find.text(AppStrings.sendOtpCta));
    await tester.pump();

    expect(gateway.otpCalls, ['01000000002']);
    expect(navigated, isTrue);
  });

  testWidgets('trims leading and trailing whitespace from phone number', (
    tester,
  ) async {
    final gateway = FakeAuthGateway();
    String? sentPhone;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          gateway: gateway,
          onOtpSent: (phone) => sentPhone = phone,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '  01000000002  ');
    await tester.tap(find.text(AppStrings.sendOtpCta));
    await tester.pump();

    expect(gateway.otpCalls, ['01000000002']);
    expect(sentPhone, '01000000002');
  });

  testWidgets('shows validation error for short phone', (tester) async {
    final gateway = FakeAuthGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(gateway: gateway, onOtpSent: (_) {}),
      ),
    );

    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text(AppStrings.sendOtpCta));
    await tester.pump();

    expect(find.text(AppStrings.invalidPhone), findsOneWidget);
    expect(gateway.otpCalls, isEmpty);
  });

  testWidgets('shows error message when SMS send fails', (tester) async {
    final gateway = FakeAuthGateway()..sendSucceeds = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(gateway: gateway, onOtpSent: (_) {}),
      ),
    );

    await tester.enterText(find.byType(TextField), '01000000002');
    await tester.tap(find.text(AppStrings.sendOtpCta));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.otpSendFailed), findsOneWidget);
  });
}
