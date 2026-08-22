import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/app_router.dart';
import 'package:mobile/services/app_supabase.dart';

Future<void> pumpWithRouter(
  WidgetTester tester, {
  required Widget home,
  AppSupabase? db,
}) async {
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => home),
          paymentProofRoute(db ?? UnimplementedAppSupabase()),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
}
