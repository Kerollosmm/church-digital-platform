import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/app_router.dart';
import 'package:mobile/features/auth/login_screen.dart';
import 'package:mobile/features/booking/payment_redirect_screen.dart';
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
    if (fn == 'paymob-checkout') {
      return {'checkout_url': 'https://paymob.test/x'};
    }
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
    if (fn == 'paymob-checkout') {
      return {'checkout_url': 'https://paymob.test/x'};
    }
    throw UnimplementedError('invokeFunction $fn');
  }

  FakeQuery from(String table) => FakeQuery([]);
}

void main() {
  testWidgets(
    'T1: payment-redirect route with int bookingId extra renders PaymentRedirectScreen with booking number',
    (tester) async {
      final fakeDb = FakeAppSupabase();
      final router = buildRouter(
        db: fakeDb,
        isUserLoggedIn: () => true,
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(HomeHubScreen));
      context.pushNamed(AppRoutes.paymentRedirect, extra: 42);
      await tester.pumpAndSettle();

      expect(find.byType(PaymentRedirectScreen), findsOneWidget);
      expect(find.text('#42'), findsOneWidget);
    },
  );

  testWidgets(
    'T1b: payment-redirect route with map extra renders PaymentRedirectScreen with booking number',
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
        AppRoutes.paymentRedirect,
        extra: {'bookingId': 42, 'checkoutUrl': 'https://paymob.test/x'},
      );
      await tester.pumpAndSettle();

      expect(find.byType(PaymentRedirectScreen), findsOneWidget);
      expect(find.text('#42'), findsOneWidget);
    },
  );

  testWidgets(
    'T2: payment-redirect route with payment_id map extra renders PaymentRedirectScreen with payment id',
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
        AppRoutes.paymentRedirect,
        extra: {'payment_id': 30},
      );
      await tester.pumpAndSettle();

      expect(find.byType(PaymentRedirectScreen), findsOneWidget);
      expect(find.text('#30'), findsOneWidget);
    },
  );

  testWidgets(
    'T3: payment-redirect route with invalid extra throws StateError',
    (tester) async {
      final fakeDb = FakeAppSupabase();
      final router = buildRouter(
        db: fakeDb,
        isUserLoggedIn: () => true,
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(HomeHubScreen));
      context.pushNamed(AppRoutes.paymentRedirect, extra: 'garbage');
      await tester.pump();

      expect(tester.takeException(), isStateError);
    },
  );

  testWidgets('T4: home route renders HomeHubScreen', (tester) async {
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
    'T5: unauthenticated user stays on home (no redirect to /login)',
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
}
