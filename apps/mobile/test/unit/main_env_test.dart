import 'package:flutter_test/flutter_test.dart';

void validateSupabaseAnonKey(String key) {
  if (key.isEmpty) {
    throw StateError(
      'Missing SUPABASE_ANON_KEY. Pass via --dart-define=SUPABASE_ANON_KEY=<key>',
    );
  }
}

void main() {
  test('validateSupabaseAnonKey throws StateError when empty', () {
    expect(() => validateSupabaseAnonKey(''), throwsA(isA<StateError>()));
  });

  test('validateSupabaseAnonKey passes when non-empty', () {
    expect(() => validateSupabaseAnonKey('valid-anon-key'), returnsNormally);
  });
}
