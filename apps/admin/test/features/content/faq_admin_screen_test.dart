import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/content/content_repository.dart';
import 'package:admin/features/content/faq_admin_screen.dart';
import '../../helpers/mock_supabase.dart';

void main() {
  testWidgets('faq admin lists rows and creates a new one', (tester) async {
    final mock = MockSupabase(tables: {
      'faq': [
        {'id': 1, 'question_ar': 'س؟', 'answer_ar': 'ج', 'position': 1, 'published': true}
      ],
    });
    final client = mock.build();
    final repo = ContentRepository(client);
    await tester.pumpWidget(MaterialApp(home: FaqAdminScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('س؟'), findsOneWidget);
    await tester.tap(find.text('إضافة سؤال'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'سؤال جديد');
    await tester.enterText(find.byType(TextField).at(1), 'إجابة جديدة');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(mock.data['faq']!.any((r) => r['question_ar'] == 'سؤال جديد'), isTrue);
  });
}
