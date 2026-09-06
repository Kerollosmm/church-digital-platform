import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/portal/portal_repository.dart';
import 'package:mobile/screens/home_hub_screen.dart';
import 'package:mobile/services/app_strings.dart';
import 'package:mobile/theme/app_theme.dart';
import '../helpers/fake_supabase.dart';

void main() {
  testWidgets(
    'HomeHubScreen renders announcements, quick actions, and verse text',
    (tester) async {
      final fake = FakeSupabase({
        'announcements': [
          {'title_ar': 'قداس عيد الميلاد المجيد', 'body_ar': 'ندعوكم للحضور'},
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: HomeHubScreen(repository: PortalRepository(fake)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('إعلانات هامة'), findsOneWidget);
      expect(find.text('قداس عيد الميلاد المجيد'), findsOneWidget);
      expect(find.text('ندعوكم للحضور'), findsOneWidget);
      expect(find.text('مواعيد القداسات'), findsOneWidget);
      expect(find.text('صندوق الشكاوى'), findsOneWidget);
      expect(find.text(AppStrings.verseText), findsOneWidget);
    },
  );

  testWidgets('HomeHubScreen shows empty state when announcements empty', (
    tester,
  ) async {
    final emptyFake = FakeSupabase({'announcements': []});
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomeHubScreen(repository: PortalRepository(emptyFake)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.noAnnouncements), findsOneWidget);
  });
}
