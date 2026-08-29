import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth/admin_auth_provider.dart';
import 'features/analytics/analytics_admin_screen.dart';
import 'features/auth/admin_login_screen.dart';

import 'features/allocation/allocation_matrix_screen.dart';
import 'features/bookings/event_bookings_admin_repository.dart';
import 'features/bookings/bookings_admin_screen.dart';
import 'features/bookings/emergency_override_screen.dart';
import 'features/bookings/manual_book_screen.dart';
import 'features/complaints/complaints_admin_screen.dart';
import 'features/content/announcements_admin_screen.dart';
import 'features/bookings/bookings_provider.dart';
import 'features/slots/slots_admin_repository.dart';
import 'features/bookings/manual_book_repository.dart';
import 'features/bookings/emergency_override_repository.dart';
import 'features/complaints/complaints_admin_repository.dart';
import 'features/content/announcements_repository.dart';
import 'features/payments/payments_admin_repository.dart';
import 'features/content/content_repository.dart';
import 'features/content/faq_admin_screen.dart';
import 'features/payments/payment_review_queue_screen.dart';
import 'features/payments/payments_admin_screen.dart';
import 'features/payments/payouts_config_screen.dart';
import 'features/slots/slots_admin_screen.dart';
import 'features/sunday_school/sunday_school_admin_dashboard.dart';
import 'features/sunday_school/sunday_school_admin_repository.dart';
import 'features/sacraments/sacramental_registrar_screen.dart';
import 'features/sacraments/sacraments_admin_repository.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 250,
            child: Drawer(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const DrawerHeader(
                    decoration: BoxDecoration(color: Colors.blue),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'لوحة الإدارة',
                        style: TextStyle(color: Colors.white, fontSize: 20),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('الحجوزات'),
                    selected: location == '/bookings',
                    onTap: () => context.go('/bookings'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.view_timeline_outlined),
                    title: const Text('تخصيص القاعات والكهنة'),
                    selected: location == '/allocation-matrix',
                    onTap: () => context.go('/allocation-matrix'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: const Text('المواعيد'),
                    selected: location == '/slots',
                    onTap: () => context.go('/slots'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_calendar),
                    title: const Text('حجز يدوي'),
                    selected: location == '/manual-book',
                    onTap: () => context.go('/manual-book'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.warning),
                    title: const Text('طوارئ'),
                    selected: location == '/emergency-override',
                    onTap: () => context.go('/emergency-override'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.feedback),
                    title: const Text('الشكاوى'),
                    selected: location == '/complaints',
                    onTap: () => context.go('/complaints'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.campaign),
                    title: const Text('الإعلانات'),
                    selected: location == '/announcements',
                    onTap: () => context.go('/announcements'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('الأسئلة الشائعة'),
                    selected: location == '/faq',
                    onTap: () => context.go('/faq'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.verified),
                    title: const Text('مراجعة إثباتات الدفع'),
                    selected: location == '/payment-review',
                    onTap: () => context.go('/payment-review'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.payment),
                    title: const Text('المدفوعات'),
                    selected: location == '/payments',
                    onTap: () => context.go('/payments'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.account_balance),
                    title: const Text('حسابات التحصيل'),
                    selected: location == '/payouts-config',
                    onTap: () => context.go('/payouts-config'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bar_chart),
                    title: const Text('التحليلات'),
                    selected: location == '/analytics',
                    onTap: () => context.go('/analytics'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.workspace_premium),
                    title: const Text('السجلات والشهادات الكنسية'),
                    selected: location == '/sacramental-records',
                    onTap: () => context.go('/sacramental-records'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.school),
                    title: const Text('مدارس الأحد'),
                    selected: location == '/sunday-school',
                    onTap: () => context.go('/sunday-school'),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

const allowedAdminRoles = {'ADMIN', 'SUPER_ADMIN'};

GoRouter createAdminRouter({
  bool Function()? isAuthenticated,
  String? Function()? getUserRole,
  String initialLocation = '/bookings',
  dynamic db,
  Listenable? refreshListenable,
}) {
  SupabaseClient? resolveDb() {
    if (db != null) return db as SupabaseClient;
    try {
      return Supabase.instance.client;
    } catch (e, st) {
      debugPrint('resolveDb fallback: $e\n$st');
      return null;
    }
  }

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final isAuthed = isAuthenticated != null
          ? isAuthenticated()
          : (resolveDb() is SupabaseClient
                ? (resolveDb() as SupabaseClient).auth.currentUser != null
                : false);
      final role = getUserRole != null ? getUserRole() : null;
      final hasAllowedRole = role != null && allowedAdminRoles.contains(role);
      final isAllowed = isAuthed && hasAllowedRole;
      final loggingIn = state.uri.path == '/login';
      if (!isAllowed) {
        return loggingIn ? null : '/login';
      }
      if (loggingIn) {
        return '/bookings';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const AdminLoginScreen(),
      ),
      GoRoute(path: '/', redirect: (_, _) => '/bookings'),
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: '/bookings',
            name: 'bookings',
            builder: (context, state) => BookingsAdminScreen(
              gateway: SupabaseBookingsGateway(resolveDb()!),
            ),
          ),
          GoRoute(
            path: '/allocation-matrix',
            name: 'allocation-matrix',
            builder: (context, state) => AllocationMatrixCalendarScreen(
              repository: SupabaseEventBookingsAdminRepository(
                client: resolveDb(),
              ),
            ),
          ),
          GoRoute(
            path: '/slots',
            name: 'slots',
            builder: (context, state) =>
                SlotsAdminScreen(repo: SlotsAdminRepository(resolveDb()!)),
          ),
          GoRoute(
            path: '/manual-book',
            name: 'manual-book',
            builder: (context, state) =>
                ManualBookScreen(repo: ManualBookRepository(resolveDb()!)),
          ),
          GoRoute(
            path: '/emergency-override',
            name: 'emergency-override',
            builder: (context, state) => EmergencyOverrideScreen(
              repo: EmergencyOverrideRepository(resolveDb()!),
            ),
          ),
          GoRoute(
            path: '/complaints',
            name: 'complaints',
            builder: (context, state) => ComplaintsAdminScreen(
              repo: ComplaintsAdminRepository(resolveDb()!),
            ),
          ),
          GoRoute(
            path: '/announcements',
            name: 'announcements',
            builder: (context, state) => AnnouncementsAdminScreen(
              repo: AnnouncementsRepository(resolveDb()!),
            ),
          ),
          GoRoute(
            path: '/faq',
            name: 'faq',
            builder: (context, state) =>
                FaqAdminScreen(repository: ContentRepository(resolveDb()!)),
          ),
          GoRoute(
            path: '/payment-review',
            name: 'payment-review',
            builder: (context, state) => PaymentReviewQueueScreen(
              repo: PaymentsAdminRepository(resolveDb()!),
            ),
          ),
          GoRoute(
            path: '/payments',
            name: 'payments',
            builder: (context, state) => PaymentsAdminScreen(
              repo: PaymentsAdminRepository(resolveDb()!),
            ),
          ),
          GoRoute(
            path: '/payouts-config',
            name: 'payouts-config',
            builder: (context, state) => PayoutsConfigScreen(
              repo: PaymentsAdminRepository(resolveDb()!),
            ),
          ),
          GoRoute(
            path: '/analytics',
            name: 'analytics',
            builder: (context, state) {
              final database = resolveDb();
              return AnalyticsAdminScreen(client: database);
            },
          ),
          GoRoute(
            path: '/sacramental-records',
            name: 'sacramental-records',
            builder: (context, state) {
              final database = resolveDb();
              return SacramentalRegistrarScreen(
                repository: SupabaseSacramentsAdminRepository(client: database),
              );
            },
          ),
          GoRoute(
            path: '/sacraments',
            redirect: (_, _) => '/sacramental-records',
          ),
          GoRoute(
            path: '/sunday-school',
            name: 'sunday-school',
            builder: (context, state) {
              final database = resolveDb();
              return SundaySchoolAdminDashboard(
                repository: SupabaseSundaySchoolAdminRepository(
                  client: database,
                ),
              );
            },
          ),
        ],
      ),
    ],
  );
}

class AdminAuthListenable extends ChangeNotifier {
  AdminAuthListenable(Ref ref) {
    ref.listen<AdminAuthState>(adminAuthProvider, (_, _) {
      notifyListeners();
    });
  }
}

final adminAuthListenableProvider = Provider<AdminAuthListenable>((ref) {
  return AdminAuthListenable(ref);
});

final adminRouterProvider = Provider<GoRouter>((ref) {
  final listenable = ref.watch(adminAuthListenableProvider);
  return createAdminRouter(
    isAuthenticated: () => ref.read(adminAuthProvider).isAuthenticated,
    getUserRole: () => ref.read(adminAuthProvider).role,
    refreshListenable: listenable,
  );
});

final appRouter = createAdminRouter();
