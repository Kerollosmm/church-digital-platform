import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:admin/core/auth/admin_auth_provider.dart';
import 'package:admin/features/auth/admin_login_screen.dart';

void main() {
  testWidgets('admin login screen smoke renders', (tester) async {
    final supabase = SupabaseClient(
      'https://qksgphryemrdrkwaqnxp.supabase.co',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFrc2dwaHJ5ZW1yZHJrd2FxbnhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5NTA2MjgsImV4cCI6MjEwMTUyNjYyOH0.ebxE042EdeYMHbkJnst8aq5K6RtlYgUXEpoeHuYNHvA',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(supabase)],
        child: const MaterialApp(home: AdminLoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('تسجيل دخول المشرفين'), findsOneWidget);
    expect(find.text('رقم الهاتف'), findsOneWidget);
  });
}

