import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/videos/videos_admin_screen.dart';
import '../../helpers/fake_supabase.dart';

void main() {
  testWidgets('videos admin lists videos and creates one', (tester) async {
    final fake = FakeSupabase({
      'videos': [
        {'id': 1, 'title_ar': 'عظة', 'price': 30, 'privacy': 'UNLISTED', 'created_at': '2026-08-05T00:00:00Z'}
      ],
    });
    await tester.pumpWidget(MaterialApp(home: VideosAdminScreen(db: fake)));
    await tester.pumpAndSettle();
    expect(find.text('عظة'), findsOneWidget);
    await tester.tap(find.text('إضافة فيديو'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'عظة جديدة');
    await tester.enterText(find.byType(TextField).at(1), 'https://youtu.be/xyz');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(fake.data['videos']!.any((r) => r['title_ar'] == 'عظة جديدة'), isTrue);
  });
}
