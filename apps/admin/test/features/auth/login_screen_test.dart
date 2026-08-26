import 'package:admin/core/auth/auth_gateway.dart';
import 'package:admin/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

    expect(find.text('تسجيل الدخول'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '01000000002');
    await tester.tap(find.text('إرسال الرمز'));
    await tester.pump();

    expect(gateway.otpCalls, ['01000000002']);
    expect(navigated, isTrue);
  });

  testWidgets('shows validation error for short phone', (tester) async {
    final gateway = FakeAuthGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(gateway: gateway, onOtpSent: (_) {}),
      ),
    );

    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('إرسال الرمز'));
    await tester.pump();

    expect(find.text('رقم غير صحيح'), findsOneWidget);
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
    await tester.tap(find.text('إرسال الرمز'));
    await tester.pumpAndSettle();

    expect(find.text('تعذر إرسال الرمز'), findsOneWidget);
  });
}
