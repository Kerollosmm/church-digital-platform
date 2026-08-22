import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/core/result.dart';
import 'package:admin/features/payments/models/payment_proof_review.dart';
import 'package:admin/features/payments/payment_review_queue_screen.dart';
import 'package:admin/features/payments/payments_admin_repository.dart';
import '../../helpers/mock_supabase.dart';

void main() {
  group('PaymentsAdminRepository — Payment Proof Review', () {
    test('listPendingProofs returns list of pending proofs from payment_proofs table', () async {
      final mock = MockSupabase(tables: {
        'payment_proofs': [
          {
            'id': 101,
            'booking_id': 501,
            'payment_id': 201,
            'channel': 'VODAFONE_CASH',
            'sender_phone': '01000000001',
            'reference_number': 'REF101',
            'amount_claimed': 150,
            'image_path': '1/501/proof.jpg',
            'status': 'PENDING',
            'created_at': DateTime.now().toIso8601String(),
          },
        ],
      });

      final repo = PaymentsAdminRepository(mock.build());
      final res = await repo.listPendingProofs();

      expect(res.isRight, isTrue);
      final proofs = res.rightOrNull!;
      expect(proofs.length, 1);
      expect(proofs.first.id, 101);
      expect(proofs.first.bookingId, 501);
      expect(proofs.first.channel, 'VODAFONE_CASH');
      expect(proofs.first.channelDisplayName, 'فودافون كاش');
      expect(proofs.first.amountClaimed, 150);
    });

    test('approveProof calls approve_payment_proof RPC and returns Right(null)', () async {
      Map<String, dynamic>? calledArgs;
      final mock = MockSupabase(
        rpc: {
          'approve_payment_proof': (args) async {
            calledArgs = args;
            return {'booking_id': 501, 'payment_id': 201};
          },
        },
      );

      final repo = PaymentsAdminRepository(mock.build());
      final res = await repo.approveProof(101, collectorNote: 'Collected note');

      expect(res.isRight, isTrue);
      expect(calledArgs, isNotNull);
      expect(calledArgs!['p_proof_id'], 101);
      expect(calledArgs!['p_collector_note'], 'Collected note');
    });

    test('rejectProof calls reject_payment_proof RPC with reasonCode and returns Right(null)', () async {
      Map<String, dynamic>? calledArgs;
      final mock = MockSupabase(
        rpc: {
          'reject_payment_proof': (args) async {
            calledArgs = args;
            return null;
          },
        },
      );

      final repo = PaymentsAdminRepository(mock.build());
      final res = await repo.rejectProof(102, 'BAD_REQUEST');

      expect(res.isRight, isTrue);
      expect(calledArgs, isNotNull);
      expect(calledArgs!['p_proof_id'], 102);
      expect(calledArgs!['p_reason_code'], 'BAD_REQUEST');
    });
  });

  group('PaymentReviewQueueScreen Widget Tests', () {
    testWidgets('renders pending proofs and triggers approve action', (tester) async {
      bool approveCalled = false;
      final mock = MockSupabase(
        tables: {
          'payment_proofs': [
            {
              'id': 1,
              'booking_id': 42,
              'payment_id': 10,
              'channel': 'VODAFONE_CASH',
              'sender_phone': '01000000042',
              'reference_number': 'VF-4242',
              'amount_claimed': 200,
              'image_path': '1/42/screenshot.png',
              'status': 'PENDING',
              'created_at': DateTime.now().toIso8601String(),
            },
          ],
        },
        rpc: {
          'approve_payment_proof': (args) async {
            approveCalled = true;
            return {'booking_id': 42, 'payment_id': 10};
          },
        },
      );

      final repo = PaymentsAdminRepository(mock.build());
      await tester.pumpWidget(MaterialApp(
        home: PaymentReviewQueueScreen(repo: repo),
      ));

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.textContaining('حجز #42'), findsOneWidget);
      expect(find.textContaining('200'), findsOneWidget);
      expect(find.textContaining('01000000042'), findsOneWidget);
      expect(find.textContaining('VF-4242'), findsOneWidget);

      // Tap approve button
      final approveBtn = find.widgetWithText(ElevatedButton, 'قبول وتأكيد');
      expect(approveBtn, findsOneWidget);
      await tester.tap(approveBtn);
      await tester.pumpAndSettle();

      // Confirm in dialog
      final confirmBtn = find.widgetWithText(ElevatedButton, 'قبول وتأكيد الحجز');
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(approveCalled, isTrue);
    });

    testWidgets('renders reject dialog with reason picker and triggers reject action', (tester) async {
      bool rejectCalled = false;
      final mock = MockSupabase(
        tables: {
          'payment_proofs': [
            {
              'id': 2,
              'booking_id': 43,
              'payment_id': 11,
              'channel': 'INSTAPAY',
              'sender_phone': '01011112222',
              'reference_number': 'INSTA-999',
              'amount_claimed': 100,
              'image_path': '1/43/screenshot.png',
              'status': 'PENDING',
              'created_at': DateTime.now().toIso8601String(),
            },
          ],
        },
        rpc: {
          'reject_payment_proof': (args) async {
            rejectCalled = true;
            return null;
          },
        },
      );

      final repo = PaymentsAdminRepository(mock.build());
      await tester.pumpWidget(MaterialApp(
        home: PaymentReviewQueueScreen(repo: repo),
      ));

      await tester.pump();
      await tester.pumpAndSettle();

      // Tap reject button
      final rejectBtn = find.widgetWithText(OutlinedButton, 'رفض');
      expect(rejectBtn, findsOneWidget);
      await tester.tap(rejectBtn);
      await tester.pumpAndSettle();

      expect(find.text('رفض إثبات الدفع'), findsOneWidget);

      // Tap confirm reject
      final confirmRejectBtn = find.widgetWithText(ElevatedButton, 'تأكيد الرفض');
      expect(confirmRejectBtn, findsOneWidget);
      await tester.tap(confirmRejectBtn);
      await tester.pumpAndSettle();

      expect(rejectCalled, isTrue);
    });

    testWidgets('shows empty state when no pending proofs exist', (tester) async {
      final mock = MockSupabase(tables: {'payment_proofs': []});
      final repo = PaymentsAdminRepository(mock.build());

      await tester.pumpWidget(MaterialApp(
        home: PaymentReviewQueueScreen(repo: repo),
      ));

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('لا توجد إثباتات دفع قيد المراجعة حالياً'), findsOneWidget);
    });
  });
}
