import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/app_router.dart';
import 'package:mobile/features/auth/login_screen.dart';
import 'package:mobile/features/booking/payment_proof_screen.dart';
import 'package:mobile/screens/home_hub_screen.dart';
import 'package:mobile/services/app_routes.dart';
import 'package:mobile/services/app_supabase.dart';
import '../helpers/fake_supabase.dart';

class FakeAppSupabase implements AppSupabase {
  final List<String> rpcCalls = [];
  final Map<String, dynamic> rpcArgs = {};

  @override
  Future<Object?> rpc(String fn, Map<String, dynamic> params) async {
    rpcCalls.add(fn);
    rpcArgs[fn] = params;
    throw UnimplementedError('rpc $fn');
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String table, {
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
  }) async => [];

  @override
  Future<Map<String, dynamic>> invokeFunction(
    String fn, {
    Map<String, dynamic>? body,
  }) async {
    rpcCalls.add(fn);
    if (body != null) rpcArgs[fn] = body;
    throw UnimplementedError('invokeFunction $fn');
  }

  @override
  Future<String> uploadStorage(
    String bucket,
    String path,
    List<int> bytes, {
    String? contentType,
  }) async => path;

  @override
  Future<void> deleteStorage(String bucket, String path) async {}

  FakeQuery from(String table) => FakeQuery([]);
}

void main() {
  testWidgets('home route renders HomeHubScreen', (tester) async {
    final fakeDb = FakeAppSupabase();
    final router = buildRouter(
      db: fakeDb,
      isUserLoggedIn: () => true,
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(HomeHubScreen), findsOneWidget);
  });

  testWidgets(
    'unauthenticated user stays on home (no redirect to /login)',
    (tester) async {
      final fakeDb = FakeAppSupabase();
      final router = buildRouter(
        db: fakeDb,
        isUserLoggedIn: () => false,
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.byType(HomeHubScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    },
  );

  testWidgets(
    'payment-proof route renders PaymentProofScreen',
    (tester) async {
      final fakeDb = FakeAppSupabase();
      final router = buildRouter(
        db: fakeDb,
        isUserLoggedIn: () => true,
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(HomeHubScreen));
      context.pushNamed(
        AppRoutes.paymentProof,
        extra: {'bookingId': 42, 'amount': 150},
      );
      await tester.pumpAndSettle();

      expect(find.byType(PaymentProofScreen), findsOneWidget);
    },
  );
}
