import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin/screens/home_screen.dart';

void main() {
  testWidgets('home smoke renders with mocked supabase client', (tester) async {
    final supabase = SupabaseClient(
      'https://qksgphryemrdrkwaqnxp.supabase.co',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFrc2dwaHJ5ZW1yZHJrd2FxbnhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5NTA2MjgsImV4cCI6MjEwMTUyNjYyOH0.ebxE042EdeYMHbkJnst8aq5K6RtlYgUXEpoeHuYNHvA',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await tester.pumpWidget(MaterialApp(home: HomeScreen(supabase: supabase)));
    expect(find.text('لوحة إدارة الكنيسة'), findsOneWidget);
    expect(find.text('غير مسجل'), findsOneWidget);
  });
}
