import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  group('validateSupabaseAnonKey', () {
    test('throws StateError when empty', () {
      expect(() => validateSupabaseAnonKey(''), throwsA(isA<StateError>()));
    });

    test('passes when non-empty', () {
      expect(() => validateSupabaseAnonKey('valid-anon-key'), returnsNormally);
    });
  });

  group('resolveSupabaseUrl', () {
    test('throws StateError in release mode when envUrl is empty', () {
      expect(
        () => resolveSupabaseUrl(envUrl: '', isRelease: true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Missing SUPABASE_URL in release mode'),
          ),
        ),
      );
    });

    test('throws StateError in release mode when envUrl is insecure http', () {
      expect(
        () => resolveSupabaseUrl(
          envUrl: 'http://my-church.supabase.co',
          isRelease: true,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Release builds require HTTPS'),
          ),
        ),
      );
    });

    test('returns envUrl in release mode when https', () {
      const httpsUrl = 'https://my-church.supabase.co';
      final url = resolveSupabaseUrl(envUrl: httpsUrl, isRelease: true);
      expect(url, equals(httpsUrl));
    });

    test('returns envUrl in debug mode when provided', () {
      const customUrl = 'http://custom-dev-host:54321';
      final url = resolveSupabaseUrl(envUrl: customUrl, isRelease: false);
      expect(url, equals(customUrl));
    });

    test('returns localhost fallback for web in debug mode', () {
      final url = resolveSupabaseUrl(envUrl: '', isRelease: false, isWeb: true);
      expect(url, equals('http://localhost:54321'));
    });

    test('returns 10.0.2.2 fallback for android in debug mode', () {
      final url = resolveSupabaseUrl(
        envUrl: '',
        isRelease: false,
        isWeb: false,
        platform: TargetPlatform.android,
      );
      expect(url, equals('http://10.0.2.2:54321'));
    });

    test('returns 127.0.0.1 fallback for other platforms in debug mode', () {
      final url = resolveSupabaseUrl(
        envUrl: '',
        isRelease: false,
        isWeb: false,
        platform: TargetPlatform.iOS,
      );
      expect(url, equals('http://127.0.0.1:54321'));
    });
  });
}
