import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/analytics/analytics_admin_screen.dart';
import 'features/auth/admin_login_screen.dart';
import 'features/bookings/bookings_admin_screen.dart';
import 'features/bookings/emergency_override_screen.dart';
import 'features/bookings/manual_book_screen.dart';
import 'features/complaints/complaints_admin_screen.dart';
import 'features/content/announcements_admin_screen.dart';
import 'features/content/content_repository.dart';
import 'features/content/faq_admin_screen.dart';
import 'features/payments/payments_admin_screen.dart';
import 'features/slots/slots_admin_screen.dart';
import 'features/videos/videos_admin_screen.dart';

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
                    leading: const Icon(Icons.payment),
                    title: const Text('المدفوعات'),
                    selected: location == '/payments',
                    onTap: () => context.go('/payments'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bar_chart),
                    title: const Text('التحليلات'),
                    selected: location == '/analytics',
                    onTap: () => context.go('/analytics'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.video_library),
                    title: const Text('الفيديوهات'),
                    selected: location == '/videos',
                    onTap: () => context.go('/videos'),
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

GoRouter createAdminRouter({
  bool Function()? isAuthenticated,
  String initialLocation = '/bookings',
  dynamic db,
}) {
  dynamic resolveDb() {
    if (db != null) return db;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) {
      final isAuthed = isAuthenticated != null
          ? isAuthenticated()
          : (() {
              try {
                return Supabase.instance.client.auth.currentUser != null;
              } catch (_) {
                return false;
              }
            })();
      final loggingIn = state.uri.path == '/login';
      if (!isAuthed) {
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
      GoRoute(
        path: '/',
        redirect: (_, _) => '/bookings',
      ),
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: '/bookings',
            name: 'bookings',
            builder: (context, state) => BookingsAdminScreen(db: resolveDb()),
          ),
          GoRoute(
            path: '/slots',
            name: 'slots',
            builder: (context, state) => SlotsAdminScreen(db: resolveDb()),
          ),
          GoRoute(
            path: '/manual-book',
            name: 'manual-book',
            builder: (context, state) => ManualBookScreen(db: resolveDb()),
          ),
          GoRoute(
            path: '/emergency-override',
            name: 'emergency-override',
            builder: (context, state) => EmergencyOverrideScreen(db: resolveDb()),
          ),
          GoRoute(
            path: '/complaints',
            name: 'complaints',
            builder: (context, state) => ComplaintsAdminScreen(db: resolveDb()),
          ),
          GoRoute(
            path: '/announcements',
            name: 'announcements',
            builder: (context, state) => AnnouncementsAdminScreen(db: resolveDb()),
          ),
          GoRoute(
            path: '/faq',
            name: 'faq',
            builder: (context, state) => FaqAdminScreen(repository: ContentRepository(resolveDb())),
          ),
          GoRoute(
            path: '/payments',
            name: 'payments',
            builder: (context, state) => PaymentsAdminScreen(db: resolveDb()),
          ),
          GoRoute(
            path: '/analytics',
            name: 'analytics',
            builder: (context, state) {
              final database = resolveDb();
              return AnalyticsAdminScreen(client: database is SupabaseClient ? database : Supabase.instance.client);
            },
          ),
          GoRoute(
            path: '/videos',
            name: 'videos',
            builder: (context, state) => VideosAdminScreen(db: resolveDb()),
          ),
        ],
      ),
    ],
  );
}

final appRouter = createAdminRouter();
