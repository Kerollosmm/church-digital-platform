import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/complaints/complaints_models.dart';
import 'package:mobile/features/complaints/complaints_repository.dart';
import 'package:mobile/features/complaints/complaints_screen.dart';
import 'package:mobile/theme/app_theme.dart';

class FakeTestComplaintsRepository implements ComplaintsRepository {
  final List<ComplaintItem> items = [
    ComplaintItem(
      id: 101,
      category: 'عامة',
      status: 'NEW',
      createdAt: DateTime.parse('2026-08-14 10:00:00'),
    ),
    ComplaintItem(
      id: 102,
      category: 'خدمات الكنيسة',
      status: 'RESOLVED',
      createdAt: DateTime.parse('2026-08-13 15:30:00'),
    ),
  ];

  String? lastCategory;
  String? lastBody;

  @override
  Future<List<ComplaintItem>> myComplaints() async => items;

  @override
  Future<int> submitComplaint({
    required String category,
    required String body,
  }) async {
    lastCategory = category;
    lastBody = body;
    return 103;
  }
}

void main() {
  testWidgets('ComplaintsScreen renders form and previous complaints list', (
    tester,
  ) async {
    final repo = FakeTestComplaintsRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ComplaintsScreen(repository: repo, isLoggedIn: () => true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('الشكاوى والمقترحات'), findsOneWidget);
    expect(find.text('تقديم شكوى أو اقتراح جديد'), findsOneWidget);
    expect(find.text('شكاوى سابقة'), findsOneWidget);
    expect(find.text('#101'), findsOneWidget);
    expect(find.text('#102'), findsOneWidget);
    expect(find.text('جديد'), findsOneWidget);
    expect(find.text('تم الحل'), findsOneWidget);

    // Enter complaint and submit
    await tester.enterText(
      find.byType(TextFormField),
      'اقتراح لتنظيم مواعيد القداس',
    );
    await tester.tap(find.text('إرسال الشكوى بأمان'));
    await tester.pumpAndSettle();

    expect(repo.lastBody, equals('اقتراح لتنظيم مواعيد القداس'));
  });
}
