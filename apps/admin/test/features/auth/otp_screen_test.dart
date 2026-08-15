import 'package:admin/core/auth/auth_gateway.dart';
import 'package:admin/features/auth/otp_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthGateway implements AuthGateway {
  bool acceptCode = true;
  String? receivedToken;

  @override
  Future<void> sendOtp(String phone) async {}

  @override
  Future<bool> verifyOtp(String phone, String token) async {
    receivedToken = token;
    return acceptCode;
  }

  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('verifies OTP and reports success', (tester) async {
    final gateway = FakeAuthGateway();
    var signedIn = false;
    await tester.pumpWidget(MaterialApp(
      home: OtpScreen(
        phone: '01000000002',
        gateway: gateway,
        onVerified: () => signedIn = true,
      ),
    ));

    expect(find.text('رمز التحقق'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();

    expect(gateway.receivedToken, '123456');
    expect(signedIn, isTrue);
  });

  testWidgets('shows error for wrong code', (tester) async {
    final gateway = FakeAuthGateway()..acceptCode = false;
    await tester.pumpWidget(MaterialApp(
      home: OtpScreen(phone: '01000000002', gateway: gateway, onVerified: () {}),
    ));

    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();

    expect(find.text('الرمز غير صحيح'), findsOneWidget);
  });
}
