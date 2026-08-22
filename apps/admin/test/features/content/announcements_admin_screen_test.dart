import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/content/announcements_admin_screen.dart';
import 'package:admin/features/content/announcements_repository.dart';
import '../../helpers/mock_supabase.dart';

void main() {
  testWidgets('announcements admin lists and deletes', (tester) async {
    final mock = MockSupabase(tables: {
      'announcements': [
        {'id': 1, 'title_ar': 'أ', 'body_ar': 'ب', 'published_at': null}
      ],
    });
    await tester.pumpWidget(MaterialApp(home: AnnouncementsAdminScreen(repo: AnnouncementsRepository(mock.build()))));
    await tester.pumpAndSettle();
    expect(find.text('أ'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    expect(mock.data['announcements']!, isEmpty);
  });
}
