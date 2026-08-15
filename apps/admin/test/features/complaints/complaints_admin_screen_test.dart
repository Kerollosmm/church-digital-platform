import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/complaints/complaints_admin_screen.dart';
import '../../helpers/fake_supabase.dart';

void main() {
  testWidgets('ComplaintsAdminScreen renders complaint list from v_complaints and decrypts body on demand', (tester) async {
    final fake = FakeSupabase(
      {
        'v_complaints': [
          {
            'id': 10,
            'user_id': 'u100',
            'category': 'خدمات',
            'status': 'NEW',
            'assigned_to': null,
            'created_at': '2026-08-11T12:00:00Z',
          },
          {
            'id': 11,
            'user_id': 'u101',
            'category': 'تنظيم',
            'status': 'ASSIGNED',
            'assigned_to': 'u1',
            'created_at': '2026-08-11T13:00:00Z',
          },
        ],
      },
      rpcResults: {
        'decrypt_complaint': (Map<String, dynamic> args) => 'محتوى الشكوى السري المفكوك',
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ComplaintsAdminScreen(db: fake),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('خدمات'), findsOneWidget);
    expect(find.textContaining('تنظيم'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'NEW'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'ASSIGNED'), findsOneWidget);

    expect(find.text('فك التشفير'), findsNWidgets(2));

    await tester.tap(find.text('فك التشفير').first);
    await tester.pumpAndSettle();

    expect(fake.rpcCalls, contains('decrypt_complaint'));
    expect(fake.rpcArgs['decrypt_complaint'], {'p_complaint_id': 11});
    expect(find.text('محتوى الشكوى السري المفكوك'), findsOneWidget);
  });
}
