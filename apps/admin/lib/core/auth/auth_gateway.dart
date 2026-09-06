import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AuthGateway {
  Future<void> sendOtp(String phone);
  Future<bool> verifyOtp(String phone, String token);
  Future<void> signOut();
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<void> sendOtp(String phone) =>
      _client.auth.signInWithOtp(phone: phone);

  @override
  Future<bool> verifyOtp(String phone, String token) async {
    try {
      final response = await _client.auth.verifyOTP(
        type: OtpType.sms,
        phone: phone,
        token: token,
      );
      return response.session != null;
    } on AuthException {
      return false;
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
