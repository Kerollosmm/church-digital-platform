import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AdminAuthStatus {
  initial,
  loading,
  authenticated,
  accessDenied,
  unauthenticated,
  pinRequired,
  pinSetupRequired,
}

const Object _unset = Object();

class AdminAuthState {
  final AdminAuthStatus status;
  final User? user;
  final String? role;
  final String? errorMessage;

  const AdminAuthState({
    this.status = AdminAuthStatus.initial,
    this.user,
    this.role,
    this.errorMessage,
  });

  bool get isAuthenticated => status == AdminAuthStatus.authenticated;
  bool get isAccessDenied => status == AdminAuthStatus.accessDenied;
  bool get isLoading => status == AdminAuthStatus.loading;
  bool get isPinRequired => status == AdminAuthStatus.pinRequired;
  bool get isPinSetupRequired => status == AdminAuthStatus.pinSetupRequired;

  AdminAuthState copyWith({
    AdminAuthStatus? status,
    User? user,
    String? role,
    Object? errorMessage = _unset,
  }) {
    return AdminAuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      role: role ?? this.role,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

class AdminAuthNotifier extends Notifier<AdminAuthState> {
  @override
  AdminAuthState build() {
    final client = ref.watch(supabaseClientProvider);
    final currentUser = client.auth.currentUser;
    if (currentUser != null) {
      _verifyRole(currentUser);
    }
    return const AdminAuthState(status: AdminAuthStatus.unauthenticated);
  }

  SupabaseClient get _client => ref.read(supabaseClientProvider);

  Future<void> sendOtp(String phone) async {
    state = state.copyWith(status: AdminAuthStatus.loading, errorMessage: null);
    try {
      await _client.auth.signInWithOtp(phone: phone);
      state = state.copyWith(status: AdminAuthStatus.unauthenticated);
    } catch (e) {
      state = state.copyWith(
        status: AdminAuthStatus.unauthenticated,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  Future<bool> verifyOtp(String phone, String token) async {
    state = state.copyWith(status: AdminAuthStatus.loading, errorMessage: null);
    try {
      final response = await _client.auth.verifyOTP(
        type: OtpType.sms,
        phone: phone,
        token: token,
      );

      final user = response.user ?? _client.auth.currentUser;
      if (user == null) {
        state = const AdminAuthState(
          status: AdminAuthStatus.unauthenticated,
          errorMessage: 'فشل التحقق من الرمز',
        );
        return false;
      }

      return await _verifyRole(user);
    } catch (e) {
      state = state.copyWith(
        status: AdminAuthStatus.unauthenticated,
        errorMessage: 'الرمز غير صحيح أو منتهي الصلاحية',
      );
      return false;
    }
  }

  Future<bool> _verifyRole(User user) async {
    state = state.copyWith(status: AdminAuthStatus.loading);
    try {
      bool isAllowed = false;
      try {
        final res = await _client.rpc('is_admin_or_priest');
        if (res is bool) {
          isAllowed = res;
        }
      } catch (_) {
        // Fallback to table query if RPC is not available (e.g. in tests)
      }

      final response = await _client
          .from('users')
          .select('role')
          .eq('id', user.id)
          .single();

      final role = response['role'] as String?;
      const allowedRoles = {'ADMIN'};


      if (isAllowed || (role != null && allowedRoles.contains(role))) {
        return await _checkPinStatus(user, role);
      } else {
        await _client.auth.signOut();
        state = const AdminAuthState(
          status: AdminAuthStatus.accessDenied,
          errorMessage: 'Access Denied / غير مصرح',
        );
        return false;
      }
    } catch (e) {
      await _client.auth.signOut();
      state = const AdminAuthState(
        status: AdminAuthStatus.accessDenied,
        errorMessage: 'Access Denied / غير مصرح',
      );
      return false;
    }
  }

  Future<bool> _checkPinStatus(User user, String? role) async {
    try {
      final statusRes = await _client.rpc('admin_pin_status');
      final statusStr = statusRes is String ? statusRes : statusRes?.toString();
      if (statusStr == 'UNSET') {
        state = AdminAuthState(
          status: AdminAuthStatus.pinSetupRequired,
          user: user,
          role: role,
        );
        return true;
      } else if (statusStr == 'LOCKED') {
        await _client.auth.signOut();
        state = const AdminAuthState(
          status: AdminAuthStatus.accessDenied,
          errorMessage: 'الحساب مغلق مؤقتاً لكثرة المحاولات الخاطئة',
        );
        return false;
      } else {
        state = AdminAuthState(
          status: AdminAuthStatus.pinRequired,
          user: user,
          role: role,
        );
        return true;
      }
    } catch (_) {
      state = AdminAuthState(
        status: AdminAuthStatus.pinRequired,
        user: user,
        role: role,
      );
      return true;
    }
  }

  Future<bool> verifyPin(String pin) async {
    state = state.copyWith(status: AdminAuthStatus.loading, errorMessage: null);
    try {
      final res = await _client.rpc('verify_admin_pin', params: {'p_pin': pin});
      if (res == true) {
        state = AdminAuthState(
          status: AdminAuthStatus.authenticated,
          user: state.user,
          role: state.role,
        );
        return true;
      } else {
        state = state.copyWith(
          status: AdminAuthStatus.pinRequired,
          errorMessage: 'رمز PIN غير صحيح',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        status: AdminAuthStatus.pinRequired,
        errorMessage: 'رمز PIN غير صحيح',
      );
      return false;
    }
  }

  Future<bool> setPin(String pin) async {
    state = state.copyWith(status: AdminAuthStatus.loading, errorMessage: null);
    try {
      await _client.rpc('set_admin_pin', params: {'p_pin': pin});
      state = AdminAuthState(
        status: AdminAuthStatus.authenticated,
        user: state.user,
        role: state.role,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        status: AdminAuthStatus.pinSetupRequired,
        errorMessage: 'فشل إعداد رمز PIN',
      );
      return false;
    }
  }


  Future<void> signOut() async {
    await _client.auth.signOut();
    state = const AdminAuthState(status: AdminAuthStatus.unauthenticated);
  }
}

final adminAuthProvider =
    NotifierProvider<AdminAuthNotifier, AdminAuthState>(AdminAuthNotifier.new);
