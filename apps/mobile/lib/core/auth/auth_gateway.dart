import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AuthGateway {
  Future<void> sendOtp(String phone);
  Future<bool> verifyOtp(String phone, String token);
  Future<void> signOut();
  bool get isAuthenticated;
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this.client);
  final SupabaseClient client;

  @override
  Future<void> sendOtp(String phone) async {
    final formatted = phone.startsWith('+20') ? phone : '+20$phone';
    await client.auth.signInWithOtp(phone: formatted);
  }

  @override
  Future<bool> verifyOtp(String phone, String token) async {
    final formatted = phone.startsWith('+20') ? phone : '+20$phone';
    final response = await client.auth.verifyOTP(
      type: OtpType.sms,
      phone: formatted,
      token: token,
    );
    return response.user != null || client.auth.currentSession != null;
  }

  @override
  Future<void> signOut() async {
    await client.auth.signOut();
  }

  @override
  bool get isAuthenticated => client.auth.currentSession != null;
}

class MockAuthGateway implements AuthGateway {
  String? lastSentPhone;
  bool _authenticated = false;

  @override
  Future<void> sendOtp(String phone) async {
    lastSentPhone = phone;
  }

  @override
  Future<bool> verifyOtp(String phone, String token) async {
    if (token == '123456' || token == '999999') {
      _authenticated = true;
      return true;
    }
    return false;
  }

  @override
  Future<void> signOut() async {
    _authenticated = false;
    lastSentPhone = null;
  }

  @override
  bool get isAuthenticated => _authenticated;
}

class UnimplementedAuthGateway implements AuthGateway {
  @override
  Future<void> sendOtp(String phone) => throw UnimplementedError();

  @override
  Future<bool> verifyOtp(String phone, String token) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  bool get isAuthenticated => false;
}
