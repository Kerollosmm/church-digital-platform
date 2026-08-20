import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:admin/app_router.dart';
import 'package:admin/core/auth/admin_auth_provider.dart';
import 'package:admin/features/auth/admin_login_screen.dart';
import '../helpers/fake_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      Supabase.instance;
    } catch (_) {
      await Supabase.initialize(
        url: 'https://qksgphryemrdrkwaqnxp.supabase.co',
        publishableKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFrc2dwaHJ5ZW1yZHJrd2FxbnhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5NTA2MjgsImV4cCI6MjEwMTUyNjYyOH0.ebxE042EdeYMHbkJnst8aq5K6RtlYgUXEpoeHuYNHvA',
        authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      );
    }
  });

  FakeSupabase createFakeDb() {
    return FakeSupabase({
      'bookings': [],
      'service_slots': [],
      'complaints': [],
      'announcements': [],
      'faq': [],
      'payments': [],
    });
  }

  testWidgets('Unauthenticated user navigating to /bookings or /analytics is redirected to /login', (tester) async {
    final router = createAdminRouter(
      isAuthenticated: () => false,
      initialLocation: '/bookings',
      db: createFakeDb(),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify redirected to AdminLoginScreen
    expect(find.byType(AdminLoginScreen), findsOneWidget);
    expect(find.text('تسجيل دخول المشرفين'), findsOneWidget);
  });

  testWidgets('Default createAdminRouter without isAuthenticated callback denies privileged access', (tester) async {
    final router = createAdminRouter(
      initialLocation: '/bookings',
      db: createFakeDb(),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Must be redirected to /login even if Supabase client instance exists
    expect(find.byType(AdminLoginScreen), findsOneWidget);
  });

  testWidgets('Authenticated user with null or unallowed role is redirected to /login', (tester) async {
    final router = createAdminRouter(
      isAuthenticated: () => true,
      getUserRole: () => null,
      db: createFakeDb(),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AdminLoginScreen), findsOneWidget);
  });

  testWidgets('Authenticated user with USER role is redirected to /login', (tester) async {
    final router = createAdminRouter(
      isAuthenticated: () => true,
      getUserRole: () => 'USER',
      db: createFakeDb(),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AdminLoginScreen), findsOneWidget);
  });

  testWidgets('Authenticated user with SUPER_ADMIN role is granted access to /bookings', (tester) async {
    final router = createAdminRouter(
      isAuthenticated: () => true,
      getUserRole: () => 'SUPER_ADMIN',
      initialLocation: '/bookings',
      db: createFakeDb(),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AdminLoginScreen), findsNothing);
  });

  testWidgets('Authenticated admin with AdminAuthStatus.authenticated is granted access to /bookings', (tester) async {
    final router = createAdminRouter(
      isAuthenticated: () => true,
      getUserRole: () => 'ADMIN',
      initialLocation: '/bookings',
      db: createFakeDb(),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Should NOT be on login screen
    expect(find.byType(AdminLoginScreen), findsNothing);
    expect(find.text('لوحة الإدارة'), findsOneWidget);
  });

  testWidgets('adminRouterProvider blocks privileged access when status is pinRequired', (tester) async {
    final container = ProviderContainer(
      overrides: [
        adminAuthProvider.overrideWith(() => _StubAuthNotifier(
          const AdminAuthState(
            status: AdminAuthStatus.pinRequired,
            role: 'ADMIN',
          ),
        )),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(adminRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdminLoginScreen), findsOneWidget);
  });

  testWidgets('adminRouterProvider blocks privileged access when status is pinSetupRequired', (tester) async {
    final container = ProviderContainer(
      overrides: [
        adminAuthProvider.overrideWith(() => _StubAuthNotifier(
          const AdminAuthState(
            status: AdminAuthStatus.pinSetupRequired,
            role: 'ADMIN',
          ),
        )),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(adminRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdminLoginScreen), findsOneWidget);
  });

}

class _StubAuthNotifier extends AdminAuthNotifier {
  _StubAuthNotifier(this._initialState);
  final AdminAuthState _initialState;

  @override
  AdminAuthState build() => _initialState;
}


