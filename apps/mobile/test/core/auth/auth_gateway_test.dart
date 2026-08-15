import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_gateway.dart';

void main() {
  group('MockAuthGateway Tests', () {
    test(
      'sendOtp stores phone and accepts fixed test OTP 123456 and 999999',
      () async {
        final gateway = MockAuthGateway();

        await gateway.sendOtp('01012345678');
        expect(gateway.lastSentPhone, equals('01012345678'));

        final wrongResult = await gateway.verifyOtp('01012345678', '000000');
        expect(wrongResult, isFalse);
        expect(gateway.isAuthenticated, isFalse);

        final validResult = await gateway.verifyOtp('01012345678', '123456');
        expect(validResult, isTrue);
        expect(gateway.isAuthenticated, isTrue);
      },
    );

    test('signOut clears authenticated session state', () async {
      final gateway = MockAuthGateway();
      await gateway.sendOtp('01012345678');
      await gateway.verifyOtp('01012345678', '123456');
      expect(gateway.isAuthenticated, isTrue);

      await gateway.signOut();
      expect(gateway.isAuthenticated, isFalse);
    });
  });
}
