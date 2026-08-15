import 'package:supabase_flutter/supabase_flutter.dart';

String normalizeEgyptPhone(String rawPhone) {
  var digits = rawPhone.replaceAll(RegExp(r'[\s\-()]'), '');
  if (digits.startsWith('+20')) {
    digits = digits.substring(3);
  } else if (digits.startsWith('0020')) {
    digits = digits.substring(4);
  } else if (digits.startsWith('20') && digits.length > 10) {
    digits = digits.substring(2);
  }
  if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return '+20$digits';
}

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
    final formatted = normalizeEgyptPhone(phone);
    await client.auth.signInWithOtp(phone: formatted);
  }

  @override
  Future<bool> verifyOtp(String phone, String token) async {
    final formatted = normalizeEgyptPhone(phone);
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
