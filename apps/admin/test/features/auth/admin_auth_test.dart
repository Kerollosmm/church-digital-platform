import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:admin/core/auth/admin_auth_provider.dart';
import 'package:admin/features/auth/admin_login_screen.dart';

SupabaseClient createMockSupabaseClient(
  String role, {
  String pinStatus = 'SET',
  bool pinValid = true,
}) {
  final mockHttpClient = MockClient((request) async {
    final path = request.url.path;

    if (path.contains('/auth/v1/otp')) {
      return http.Response(
        '{}',
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path.contains('/auth/v1/verify')) {
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

    if (path.contains('/rest/v1/rpc/admin_pin_status')) {
      return http.Response(
        jsonEncode(pinStatus),
        200,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    if (path.contains('/rest/v1/rpc/verify_admin_pin')) {
      return http.Response(
        jsonEncode(pinValid),
        200,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    if (path.contains('/rest/v1/rpc/set_admin_pin')) {
      return http.Response(
        '{}',
        200,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    if (path.contains('/rest/v1/users')) {
      return http.Response(
        jsonEncode({'role': role}),
        200,
        request: request,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'content-range': '0-0/1',
        },
      );
    }

    if (path.contains('/auth/v1/logout')) {
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

Widget createTestApp(SupabaseClient supabaseClient) {
  return ProviderScope(
    overrides: [supabaseClientProvider.overrideWithValue(supabaseClient)],
    child: const MaterialApp(
      locale: Locale('ar'),
      supportedLocales: [Locale('ar')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AdminLoginScreen(),
    ),
  );
}

void main() {
  group('Admin Auth & Role Access Control Tests', () {
    testWidgets('USER receives "Access Denied / غير مصرح" and is signed out', (
      tester,
    ) async {
      final supabaseClient = createMockSupabaseClient('USER');

      await tester.pumpWidget(createTestApp(supabaseClient));
      await tester.pumpAndSettle();

      // Enter phone number
      final phoneField = find.byType(TextFormField).first;
      expect(phoneField, findsOneWidget);
      await tester.enterText(phoneField, '01234567890');
      await tester.tap(find.text('إرسال الرمز'));
      await tester.pumpAndSettle();

      // Enter OTP
      final otpField = find.byType(TextFormField).last;
      await tester.enterText(otpField, '123456');
      await tester.tap(find.text('تأكيد الرمز'));
      await tester.pumpAndSettle();

      // Assert error message shown & user signed out
      expect(find.textContaining('Access Denied / غير مصرح'), findsOneWidget);
      expect(supabaseClient.auth.currentUser, isNull);
    });

    testWidgets(
      'SUPER_ADMIN user with SET pin enters 3-step login successfully',
      (tester) async {
        final supabaseClient = createMockSupabaseClient(
          'SUPER_ADMIN',
          pinStatus: 'SET',
          pinValid: true,
        );

        await tester.pumpWidget(createTestApp(supabaseClient));
        await tester.pumpAndSettle();

        final phoneField = find.byType(TextFormField).first;
        await tester.enterText(phoneField, '01234567890');
        await tester.tap(find.text('إرسال الرمز'));
        await tester.pumpAndSettle();

        final otpField = find.byType(TextFormField).last;
        await tester.enterText(otpField, '123456');
        await tester.tap(find.text('تأكيد الرمز'));
        await tester.pumpAndSettle();

        expect(find.text('أدخل رمز PIN'), findsOneWidget);
      },
    );

    testWidgets('ADMIN user with SET pin enters 3-step login successfully', (
      tester,
    ) async {
      final supabaseClient = createMockSupabaseClient(
        'ADMIN',
        pinStatus: 'SET',
        pinValid: true,
      );

      await tester.pumpWidget(createTestApp(supabaseClient));
      await tester.pumpAndSettle();

      // Step 1: Phone
      final phoneField = find.byType(TextFormField).first;
      await tester.enterText(phoneField, '01234567890');
      await tester.tap(find.text('إرسال الرمز'));
      await tester.pumpAndSettle();

      // Step 2: OTP
      final otpField = find.byType(TextFormField).last;
      await tester.enterText(otpField, '123456');
      await tester.tap(find.text('تأكيد الرمز'));
      await tester.pumpAndSettle();

      // Step 3: PIN entry step requested
      expect(find.text('أدخل رمز PIN'), findsOneWidget);
      final pinField = find.byType(TextFormField).last;
      await tester.enterText(pinField, '1234');
      await tester.tap(find.text('تأكيد رمز PIN'));
      expect(supabaseClient.auth.currentUser, isNotNull);
    });

    testWidgets('ADMIN user enters wrong PIN and shows error message', (
      tester,
    ) async {
      final supabaseClient = createMockSupabaseClient(
        'ADMIN',
        pinStatus: 'SET',
        pinValid: false,
      );

      await tester.pumpWidget(createTestApp(supabaseClient));
      await tester.pumpAndSettle();

      // Step 1: Phone
      final phoneField = find.byType(TextFormField).first;
      await tester.enterText(phoneField, '01234567890');
      await tester.tap(find.text('إرسال الرمز'));
      await tester.pumpAndSettle();

      // Step 2: OTP
      final otpField = find.byType(TextFormField).last;
      await tester.enterText(otpField, '123456');
      await tester.tap(find.text('تأكيد الرمز'));
      await tester.pumpAndSettle();

      // Step 3: PIN
      expect(find.text('أدخل رمز PIN'), findsOneWidget);
      final pinField = find.byType(TextFormField).last;
      await tester.enterText(pinField, '0000');
      await tester.tap(find.text('تأكيد رمز PIN'));
      await tester.pumpAndSettle();

      expect(find.text('رمز PIN غير صحيح'), findsOneWidget);
    });

    testWidgets(
      'ADMIN user with UNSET pin sees setup form and completes setup',
      (tester) async {
        final supabaseClient = createMockSupabaseClient(
          'ADMIN',
          pinStatus: 'UNSET',
        );

        await tester.pumpWidget(createTestApp(supabaseClient));
        await tester.pumpAndSettle();

        // Step 1: Phone
        final phoneField = find.byType(TextFormField).first;
        await tester.enterText(phoneField, '01234567890');
        await tester.tap(find.text('إرسال الرمز'));
        await tester.pumpAndSettle();

        // Step 2: OTP
        final otpField = find.byType(TextFormField).last;
        await tester.enterText(otpField, '123456');
        await tester.tap(find.text('تأكيد الرمز'));
        await tester.pumpAndSettle();

        // Step 3: Setup PIN
        expect(find.text('إعداد رمز PIN جديد'), findsOneWidget);
        final fields = find.byType(TextFormField);
        expect(fields, findsNWidgets(2)); // pin & confirm pin

        await tester.enterText(fields.at(0), '1234');
        await tester.enterText(fields.at(1), '1234');
        await tester.tap(find.text('حفظ رمز PIN والدخول'));
        expect(supabaseClient.auth.currentUser, isNotNull);
      },
    );

    testWidgets('ADMIN user with LOCKED status receives lockout error', (
      tester,
    ) async {
      final supabaseClient = createMockSupabaseClient(
        'ADMIN',
        pinStatus: 'LOCKED',
      );

      await tester.pumpWidget(createTestApp(supabaseClient));
      await tester.pumpAndSettle();

      final phoneField = find.byType(TextFormField).first;
      await tester.enterText(phoneField, '01234567890');
      await tester.tap(find.text('إرسال الرمز'));
      await tester.pumpAndSettle();

      final otpField = find.byType(TextFormField).last;
      await tester.enterText(otpField, '123456');
      await tester.tap(find.text('تأكيد الرمز'));
      await tester.pumpAndSettle();

      expect(find.textContaining('الحساب مغلق'), findsOneWidget);
    });

    test(
      'AdminAuthNotifier state transitions require PIN before AdminAuthStatus.authenticated',
      () async {
        final supabaseClient = createMockSupabaseClient(
          'ADMIN',
          pinStatus: 'SET',
          pinValid: true,
        );
        final container = ProviderContainer(
          overrides: [supabaseClientProvider.overrideWithValue(supabaseClient)],
        );
        addTearDown(container.dispose);

        final notifier = container.read(adminAuthProvider.notifier);
        expect(
          container.read(adminAuthProvider).status,
          AdminAuthStatus.unauthenticated,
        );
        expect(container.read(adminAuthProvider).isAuthenticated, isFalse);

        // Verify OTP
        await notifier.sendOtp('01234567890');
        final otpSuccess = await notifier.verifyOtp('01234567890', '123456');
        expect(otpSuccess, isTrue);

        // Supabase user session exists, but status is pinRequired (NOT authenticated)
        expect(supabaseClient.auth.currentUser, isNotNull);
        expect(
          container.read(adminAuthProvider).status,
          AdminAuthStatus.pinRequired,
        );
        expect(container.read(adminAuthProvider).isAuthenticated, isFalse);

        // Verify PIN succeeds
        final pinSuccess = await notifier.verifyPin('1234');
        expect(pinSuccess, isTrue);
        expect(
          container.read(adminAuthProvider).status,
          AdminAuthStatus.authenticated,
        );
        expect(container.read(adminAuthProvider).isAuthenticated, isTrue);
      },
    );

    test('AdminAuthNotifier keeps pinRequired status on wrong PIN', () async {
      final supabaseClient = createMockSupabaseClient(
        'ADMIN',
        pinStatus: 'SET',
        pinValid: false,
      );
      final container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(supabaseClient)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(adminAuthProvider.notifier);
      await notifier.sendOtp('01234567890');
      await notifier.verifyOtp('01234567890', '123456');

      expect(
        container.read(adminAuthProvider).status,
        AdminAuthStatus.pinRequired,
      );
      expect(container.read(adminAuthProvider).isAuthenticated, isFalse);

      // Wrong PIN
      final pinSuccess = await notifier.verifyPin('0000');
      expect(pinSuccess, isFalse);
      expect(
        container.read(adminAuthProvider).status,
        AdminAuthStatus.pinRequired,
      );
      expect(container.read(adminAuthProvider).isAuthenticated, isFalse);
      expect(
        container.read(adminAuthProvider).errorMessage,
        'رمز PIN غير صحيح',
      );
    });
  });
}
