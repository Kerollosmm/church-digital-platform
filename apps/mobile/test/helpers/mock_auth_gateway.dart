import 'package:mobile/core/auth/auth_gateway.dart';

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
