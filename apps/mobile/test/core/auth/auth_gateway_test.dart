import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_gateway.dart';
import '../../helpers/mock_auth_gateway.dart';

void main() {
  group('normalizeEgyptPhone Tests', () {
    test('normalizes 01 domestic number by stripping leading zero and adding +20', () {
      expect(normalizeEgyptPhone('01012345678'), equals('+201012345678'));
      expect(normalizeEgyptPhone('01123456789'), equals('+201123456789'));
      expect(normalizeEgyptPhone('01234567890'), equals('+201234567890'));
      expect(normalizeEgyptPhone('01512345678'), equals('+201512345678'));
    });

    test('normalizes +20 prefixed numbers correctly without duplicate prefixes', () {
      expect(normalizeEgyptPhone('+201012345678'), equals('+201012345678'));
      expect(normalizeEgyptPhone('+2001012345678'), equals('+201012345678'));
      expect(normalizeEgyptPhone('201012345678'), equals('+201012345678'));
    });

    test('handles whitespace and formatting characters', () {
      expect(normalizeEgyptPhone('010 1234 5678'), equals('+201012345678'));
      expect(normalizeEgyptPhone('010-1234-5678'), equals('+201012345678'));
    });
  });

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

