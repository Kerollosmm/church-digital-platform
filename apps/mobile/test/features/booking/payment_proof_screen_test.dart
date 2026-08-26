import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/either.dart';
import 'package:mobile/core/failure.dart';
import 'package:mobile/features/booking/payment_proof_screen.dart';
import 'package:mobile/models/available_slot.dart';
import 'package:mobile/models/booking.dart';
import 'package:mobile/models/payment_channel.dart';
import 'package:mobile/models/payment_proof.dart';
import 'package:mobile/models/payment_proof_input.dart';
import 'package:mobile/models/payout_channel.dart';
import 'package:mobile/repositories/booking_repository.dart';
import 'package:mobile/services/app_strings.dart';

class FakeProofBookingRepository implements BookingRepository {
  List<PayoutChannel> payoutChannels = [
    const PayoutChannel(
      id: 1,
      channel: PaymentChannel.vodafoneCash,
      displayNameAr: 'فودافون كاش',
      accountNumber: '01000000000',
      holderName: 'الكنيسة القبطية',
    ),
    const PayoutChannel(
      id: 2,
      channel: PaymentChannel.instaPay,
      displayNameAr: 'إنستاباي',
      accountNumber: 'church@instapay',
      holderName: 'الكنيسة القبطية',
    ),
  ];

  PaymentProofInput? lastSubmittedInput;
  Either<Failure, int> submitResult = const Right(42);
  Either<Failure, String> uploadResult = const Right('1/101/proof.jpg');

  @override
  Future<Either<Failure, List<PayoutChannel>>> fetchPayoutChannels() async {
    return Right(payoutChannels);
  }

  @override
  Future<Either<Failure, int>> submitPaymentProof(
    PaymentProofInput input,
  ) async {
    lastSubmittedInput = input;
    return submitResult;
  }

  @override
  Future<Either<Failure, String>> uploadProofImage({
    required int bookingId,
    required Uint8List bytes,
    required String filename,
  }) async {
    return uploadResult;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchServices() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchSlotsForService(
    int serviceId,
  ) async => [];
  @override
  Future<List<AvailableSlot>> fetchAvailableSlots() async => [];
  @override
  Future<List<Booking>> fetchMyBookings() async => [];
  @override
  Future<Either<Failure, Booking>> reserveAndPay({
    required int slotId,
    bool whatsappOptIn = false,
  }) async => const Left(BookingFailure('Unused in this test'));
  @override
  Future<void> cancelBooking(int bookingId) async {}
  @override
  Future<void> confirmBooking(int bookingId) async {}
  @override
  Future<void> completeBooking(int bookingId) async {}
  @override
  Future<Either<Failure, PaymentProof>> fetchLatestProof(int bookingId) async =>
      const Left(BookingFailure('no proof'));
  @override
  Future<Either<Failure, void>> deleteProofImage(String path) async =>
      const Right(null);
}

void main() {
  group('PaymentProofScreen', () {
    late FakeProofBookingRepository repository;

    setUp(() {
      repository = FakeProofBookingRepository();
    });

    Widget buildTestWidget({int bookingId = 101, int amount = 150}) {
      return MaterialApp(
        home: PaymentProofScreen(
          bookingId: bookingId,
          amount: amount,
          repository: repository,
        ),
      );
    }

    testWidgets('renders payout channels and form fields', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.paymentProofTitle), findsOneWidget);
      expect(find.text('01000000000'), findsWidgets);
      expect(find.text('الكنيسة القبطية'), findsOneWidget);
      expect(find.byType(TextFormField), findsWidgets);
      expect(find.text(AppStrings.submitProof), findsOneWidget);
    });

    testWidgets('shows error when submitting wallet without image attached', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Enter sender phone and reference number
      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), '01012345678');
      await tester.enterText(textFields.at(1), 'TXN998877');
      await tester.pumpAndSettle();

      final submitBtn = find.text(AppStrings.submitProof);
      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();

      // Submit without image
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.proofImageRequired), findsOneWidget);
      expect(repository.lastSubmittedInput, isNull);
    });

    testWidgets(
      'submits successfully when cash channel selected (no image needed)',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Switch to CASH
        await tester.tap(find.text(AppStrings.cashInPerson));
        await tester.pumpAndSettle();

        final textFields = find.byType(TextFormField);
        await tester.enterText(textFields.at(0), '01012345678');
        await tester.enterText(textFields.at(1), 'TALAB123');
        await tester.pumpAndSettle();

        final submitBtn = find.text(AppStrings.submitProof);
        await tester.ensureVisible(submitBtn);
        await tester.pumpAndSettle();

        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        expect(repository.lastSubmittedInput, isNotNull);
        expect(repository.lastSubmittedInput!.channel, PaymentChannel.cash);
        expect(repository.lastSubmittedInput!.referenceNumber, 'TALAB123');
        expect(repository.lastSubmittedInput!.imagePath, isNull);
        expect(find.text(AppStrings.proofSubmittedSuccess), findsOneWidget);
      },
    );

    testWidgets(
      'dynamically renders updated payout channels returned by repository',
      (tester) async {
        repository.payoutChannels = [
          const PayoutChannel(
            id: 10,
            channel: PaymentChannel.vodafoneCash,
            displayNameAr: 'محفظة الكنيسة المحدثة',
            accountNumber: '01099998888',
            holderName: 'أبونا مقار',
          ),
        ];

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('محفظة الكنيسة المحدثة'), findsOneWidget);
        expect(find.text('01099998888'), findsWidgets);
        expect(find.text('أبونا مقار'), findsOneWidget);
      },
    );
  });
}
