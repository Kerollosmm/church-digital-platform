import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/portal/portal_models.dart';
import 'package:mobile/features/portal/portal_repository.dart';
import 'package:mobile/features/portal/priests_directory_sheet.dart';
import 'package:mobile/theme/app_theme.dart';

class FakePriestsPortalRepository implements PortalRepository {
  @override
  Future<List<AnnouncementItem>> announcements() async => [];

  @override
  Future<List<TodayScheduleItem>> todaySchedule() async => [];

  @override
  Future<List<SocialLinkItem>> socialLinks() async => [];

  @override
  Future<List<PriestItem>> priests() async => [
    const PriestItem(
      id: 'p1',
      name: 'القمص متى',
      bio: 'كاهن كنيسة الشهيد مارمرقس',
      visitationHours: 'الأحد والثلاثاء ٥-٨ م',
    ),
  ];
}

void main() {
  testWidgets('PriestsDirectorySheet displays priests and confession hours', (
    tester,
  ) async {
    final repo = FakePriestsPortalRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => PriestsDirectorySheet.show(context, repo),
              child: const Text('Show Priests'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show Priests'));
    await tester.pumpAndSettle();

    expect(find.text('الآباء الكهنة ومواعيد الاعترافات'), findsOneWidget);
    expect(find.text('القمص متى'), findsOneWidget);
    expect(find.text('كاهن كنيسة الشهيد مارمرقس'), findsOneWidget);
    expect(find.textContaining('الأحد والثلاثاء ٥-٨ م'), findsOneWidget);
  });
}
