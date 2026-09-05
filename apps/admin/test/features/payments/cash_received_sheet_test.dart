import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin/features/payments/cash_received_sheet.dart';
import 'package:admin/features/payments/payments_admin_repository.dart';
import '../../helpers/mock_supabase.dart';

void main() {
  group('CashReceivedSheet Widget Tests', () {
    testWidgets('renders initial amount and submittal triggers repository', (
      tester,
    ) async {
      Map<String, dynamic>? calledArgs;
      final mock = MockSupabase(
        rpc: {
          'mark_cash_received': (args) async {
            calledArgs = args;
            return {'proof_id': 1, 'booking_id': 801, 'payment_id': 1};
          },
        },
      );
      final repo = PaymentsAdminRepository(mock.build());
      bool successCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => CashReceivedSheet.show(
                  ctx,
                  repository: repo,
                  bookingId: 801,
                  initialAmount: 35000,
                  onSuccess: () => successCalled = true,
                ),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('استلام دفع نقدي — حجز #801'), findsOneWidget);
      expect(find.text('350'), findsOneWidget);

      await tester.tap(find.text('تأكيد استلام النقدية'));
      await tester.pumpAndSettle();

      expect(calledArgs, isNotNull);
      expect(calledArgs!['p_booking_id'], 801);
      expect(calledArgs!['p_amount'], 35000);
      expect(successCalled, isTrue);
    });

    testWidgets('shows validation error when amount is invalid', (
      tester,
    ) async {
      final mock = MockSupabase();
      final repo = PaymentsAdminRepository(mock.build());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => CashReceivedSheet.show(
                  ctx,
                  repository: repo,
                  bookingId: 802,
                  initialAmount: 0,
                ),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('تأكيد استلام النقدية'));
      await tester.pumpAndSettle();

      expect(find.text('يرجى إدخال مبلغ صحيح أكبر من الصفر'), findsOneWidget);
    });

    testWidgets('displays server error on failure', (tester) async {
      final mock = MockSupabase(
        rpc: {
          'mark_cash_received': (args) async {
            throw PostgrestException(message: 'Forbidden', code: '42501');
          },
        },
      );
      final repo = PaymentsAdminRepository(mock.build());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => CashReceivedSheet.show(
                  ctx,
                  repository: repo,
                  bookingId: 803,
                  initialAmount: 150,
                ),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('تأكيد استلام النقدية'));
      await tester.pumpAndSettle();

      expect(find.text('ليس لديك صلاحية لتنفيذ هذا الإجراء'), findsOneWidget);
    });
  });
}
