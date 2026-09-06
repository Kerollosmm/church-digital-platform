import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:admin/core/auth/admin_auth_provider.dart';

/// US4 (010-fix-review-findings): the removed priest-era RPC
/// `is_admin_or_priest` must NEVER be requested during identity checks;
/// access is decided solely from public.users.role via one round-trip,
/// with no silent catch-through between branches.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requestLog = <String>[];

  SupabaseClient buildClient(String role) {
    final mockHttpClient = MockClient((request) async {
      requestLog.add(request.url.path);
      if (request.url.path.contains('/auth/v1/verify')) {
        return http.Response(
          jsonEncode({
            'access_token': 'fake_token',
            'token_type': 'bearer',
            'expires_in': 3600,
            'refresh_token': 'fake_refresh',
            'user': {
              'id': 'user_123',
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'user@example.com',
              'phone': '+201234567890',
              'app_metadata': {'provider': 'phone'},
              'user_metadata': {},
              'created_at': '2026-01-01T00:00:00.000Z',
            },
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.url.path.contains('/rest/v1/rpc/admin_pin_status')) {
        return http.Response(jsonEncode('SET'), 200, request: request);
      }
      if (request.url.path.contains('/rest/v1/rpc/verify_admin_pin')) {
        return http.Response(jsonEncode(true), 200, request: request);
      }
      if (request.url.path.contains('/rest/v1/users')) {
        return http.Response(
          jsonEncode({'role': role}),
          200,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.url.path.contains('/auth/v1/logout')) {
        return http.Response('{}', 204, request: request);
      }
      return http.Response('Not Found', 404, request: request);
    });

    return SupabaseClient(
      'https://qksgphryemrdrkwaqnxp.supabase.co',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFrc2dwaHJ5ZW1yZHJrd2FxbnhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5NTA2MjgsImV4cCI6MjEwMTUyNjYyOH0.ebxE042EdeYMHbkJnst8aq5K6RtlYgUXEpoeHuYNHvA',
      httpClient: mockHttpClient,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  }

  Future<ProviderContainer> runIdentityCheck(String role) async {
    requestLog.clear();
    final client = buildClient(role);
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    // Drive the real identity seam end-to-end: OTP verify -> role -> PIN.
    final notifier = container.read(adminAuthProvider.notifier);
    await notifier.verifyOtp('+201234567890', '123456');
    return container;
  }

  test(
    'ADMIN identity check never calls removed is_admin_or_priest; one users round-trip',
    () async {
      final container = await runIdentityCheck('ADMIN');

      expect(
        requestLog.where((p) => p.contains('is_admin_or_priest')),
        isEmpty,
        reason: 'removed priest-era function must not be requested',
      );
      expect(
        requestLog.where((p) => p.contains('/rest/v1/users')).length,
        1,
        reason: 'exactly one role round-trip expected',
      );
      expect(
        container.read(adminAuthProvider).status,
        AdminAuthStatus.pinRequired,
      );
    },
  );

  test('USER-role member denied without dead-RPC fallback', () async {
    final container = await runIdentityCheck('USER');

    expect(requestLog.any((p) => p.contains('is_admin_or_priest')), isFalse);
    expect(
      container.read(adminAuthProvider).status,
      AdminAuthStatus.accessDenied,
    );
  });
}
