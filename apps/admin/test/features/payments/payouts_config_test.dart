import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/core/result.dart';
import 'package:admin/features/payments/models/payout_channel.dart';
import 'package:admin/features/payments/payments_admin_repository.dart';
import 'package:admin/features/payments/payouts_config_screen.dart';
import '../../helpers/mock_supabase.dart';

void main() {
  final sampleChannels = [
    {
      'id': 1,
      'channel': 'VODAFONE_CASH',
      'display_name_ar': 'فودافون كاش',
      'account_number': '01012345678',
      'holder_name': 'كنيسة مارجرجس',
    },
    {
      'id': 2,
      'channel': 'INSTAPAY',
      'display_name_ar': 'إنستاباي',
      'account_number': 'church@instapay',
      'holder_name': 'كنيسة مارجرجس',
    },
  ];

  group('PayoutsConfigScreen Widget Tests', () {
    testWidgets(
      'renders payout channels and hides edit buttons for regular ADMIN',
      (tester) async {
        final mock = MockSupabase(tables: {'payout_channels': sampleChannels});
        final repo = PaymentsAdminRepository(mock.build());

        await tester.pumpWidget(
          MaterialApp(
            home: PayoutsConfigScreen(repo: repo, isSuperAdminOverride: false),
          ),
        );

        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('فودافون كاش'), findsOneWidget);
        expect(find.text('01012345678'), findsOneWidget);
        expect(find.text('إنستاباي'), findsOneWidget);
        expect(find.text('church@instapay'), findsOneWidget);

        // Read-only notice present
        expect(
          find.textContaining('عرض تفاصيل الحسابات متاح للقراءة فقط'),
          findsOneWidget,
        );

        // Edit buttons hidden
        expect(find.byIcon(Icons.edit), findsNothing);
      },
    );

    testWidgets(
      'shows edit buttons for SUPER_ADMIN and permits editing channel',
      (tester) async {
        final mock = MockSupabase(tables: {'payout_channels': sampleChannels});
        final repo = PaymentsAdminRepository(mock.build());

        await tester.pumpWidget(
          MaterialApp(
            home: PayoutsConfigScreen(repo: repo, isSuperAdminOverride: true),
          ),
        );

        await tester.pump();
        await tester.pumpAndSettle();

        // Read-only notice absent
        expect(
          find.textContaining('عرض تفاصيل الحسابات متاح للقراءة فقط'),
          findsNothing,
        );

        // Edit buttons present
        final editBtns = find.byIcon(Icons.edit);
        expect(editBtns, findsNWidgets(2));

        // Tap first edit button
        await tester.tap(editBtns.first);
        await tester.pumpAndSettle();

        expect(find.text('تعديل بيانات فودافون كاش'), findsOneWidget);

        // Tap cancel
        final cancelBtn = find.widgetWithText(TextButton, 'إلغاء');
        expect(cancelBtn, findsOneWidget);
        await tester.tap(cancelBtn);
        await tester.pumpAndSettle();

        expect(find.text('تعديل بيانات فودافون كاش'), findsNothing);
      },
    );

    testWidgets('shows error state when load fails', (tester) async {
      final repo = FailingPayoutsRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: PayoutsConfigScreen(repo: repo, isSuperAdminOverride: false),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('فشل في جلب البيانات'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });
  });

  group('PaymentsAdminRepository Payout Channels Unit Tests', () {
    test('listPayoutChannels returns list of PayoutChannel models', () async {
      final mock = MockSupabase(tables: {'payout_channels': sampleChannels});
      final repo = PaymentsAdminRepository(mock.build());

      final res = await repo.listPayoutChannels();
      expect(res.isRight, isTrue);
      final list = res.rightOrNull!;
      expect(list.length, 2);
      expect(list.first.channel, 'VODAFONE_CASH');
      expect(list.first.accountNumber, '01012345678');
    });

    test('upsertPayoutChannel executes update and returns Right(null)', () async {
      final mock = MockSupabase(tables: {'payout_channels': sampleChannels});
      final repo = PaymentsAdminRepository(mock.build());

      final res = await repo.upsertPayoutChannel(
        const PayoutChannel(
          channel: 'VODAFONE_CASH',
          displayNameAr: 'فودافون كاش المحدث',
          accountNumber: '01099999999',
          holderName: 'مطرانية الكنيسة',
        ),
      );

      expect(res.isRight, isTrue);
    });
  });
}

class FailingPayoutsRepository extends PaymentsAdminRepository {
  FailingPayoutsRepository() : super(MockSupabase().build());

  @override
  Future<Either<Failure, List<PayoutChannel>>> listPayoutChannels() async {
    return const Left(
      Failure(code: 'NETWORK_ERROR', message: 'فشل في جلب البيانات'),
    );
  }
}
