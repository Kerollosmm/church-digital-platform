import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_gateway.dart';
import 'package:mobile/core/auth/phone_verify_gate.dart';
import 'package:mobile/services/app_strings.dart';

class FakeAuthGateway implements AuthGateway {
  final sendCalls = <String>[];
  final verifyCalls = <String>[];
  bool verifyReturns = true;

  @override
  Future<void> sendOtp(String phone) async {
    sendCalls.add(phone);
  }

  @override
  Future<bool> verifyOtp(String phone, String token) async {
    verifyCalls.add('$phone:$token');
    return verifyReturns;
  }

  @override
  Future<void> signOut() async {}

  @override
  bool get isAuthenticated => false;
}

void main() {
  test('checkSession fails closed when Supabase is not initialized', () {
    // In the test zone Supabase.instance throws (never initialized).
    // Injected callbacks remain authoritative when provided:
    expect(PhoneVerifyGate.checkSession(() => true), isTrue);
    expect(PhoneVerifyGate.checkSession(() => false), isFalse);
    // Uninitialized client must NOT be treated as logged in:
    expect(PhoneVerifyGate.checkSession(), isFalse);
  });

  testWidgets('PhoneVerifyGate skips verification when session exists', (
    tester,
  ) async {
    final gateway = FakeAuthGateway();
    var verifiedCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: PhoneVerifyGate(
          gateway: gateway,
          isLoggedIn: () => true,
          onVerified: () => verifiedCalled = true,
          child: const Text('Protected Content'),
        ),
      ),
    );

    expect(find.text('Protected Content'), findsOneWidget);
    expect(find.text(AppStrings.phoneLabel), findsNothing);
    expect(gateway.sendCalls, isEmpty);
    expect(verifiedCalled, isFalse);
  });

  testWidgets(
    'PhoneVerifyGate shows phone step when logged out, enters phone -> OTP -> verifies -> shows child',
    (tester) async {
      final gateway = FakeAuthGateway();
      var verifiedCalled = false;
      var loggedInState = false;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return PhoneVerifyGate(
                gateway: gateway,
                isLoggedIn: () => loggedInState,
                onVerified: () {
                  verifiedCalled = true;
                  setState(() => loggedInState = true);
                },
                child: const Text('Protected Content'),
              );
            },
          ),
        ),
      );

      // Initial state: phone input screen
      expect(find.text('Protected Content'), findsNothing);
      expect(find.text(AppStrings.authTitle), findsOneWidget);
      expect(find.text(AppStrings.phoneLabel), findsOneWidget);

      // Enter phone and submit
      await tester.enterText(find.byType(TextField), '01012345678');
      await tester.tap(find.text(AppStrings.sendOtpCta));
      await tester.pumpAndSettle();

      expect(gateway.sendCalls, ['01012345678']);

      // Now in OTP step
      expect(find.text(AppStrings.otpIntro), findsOneWidget);
      expect(find.text('+20 01012345678'), findsOneWidget);

      final otpFields = find.byType(TextField);
      expect(otpFields, findsNWidgets(6));
      for (var i = 0; i < 6; i++) {
        await tester.enterText(otpFields.at(i), '${i + 1}');
      }
      await tester.pumpAndSettle();

      expect(gateway.verifyCalls, ['01012345678:123456']);
      expect(verifiedCalled, isTrue);
      expect(find.text('Protected Content'), findsOneWidget);
    },
  );

  testWidgets('PhoneVerifyGate.ensureAuth bypasses when logged in', (
    tester,
  ) async {
    final gateway = FakeAuthGateway();
    var actionRan = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => PhoneVerifyGate.ensureAuth(
                context,
                gateway: gateway,
                isLoggedIn: () => true,
                onVerified: () => actionRan = true,
              ),
              child: const Text('Action'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();

    expect(actionRan, isTrue);
    expect(find.text(AppStrings.phoneLabel), findsNothing);
  });

  testWidgets(
    'PhoneVerifyGate.ensureAuth prompts bottom sheet when logged out and executes action after verify',
    (tester) async {
      final gateway = FakeAuthGateway();
      var actionRan = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PhoneVerifyGate.ensureAuth(
                  context,
                  gateway: gateway,
                  isLoggedIn: () => false,
                  onVerified: () => actionRan = true,
                ),
                child: const Text('Action'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();

      // Bottom sheet with phone step appears
      expect(find.text(AppStrings.authTitle), findsOneWidget);
      expect(find.text(AppStrings.phoneLabel), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '01099999999');
      await tester.tap(find.text(AppStrings.sendOtpCta));
      await tester.pumpAndSettle();

      final otpFields = find.byType(TextField);
      for (var i = 0; i < 6; i++) {
        await tester.enterText(otpFields.at(i), '9');
      }
      await tester.pumpAndSettle();

      expect(gateway.verifyCalls, ['01099999999:999999']);
      expect(actionRan, isTrue);
    },
  );
}
