import '../core/either.dart';
import '../core/failure.dart';
import '../models/book_slot_result.dart';
import '../models/booking_checkout_session.dart';
import '../repositories/booking_repository.dart';
import '../services/app_strings.dart';

class BookingFlowController {
  BookingFlowController(this._repository);
  final BookingRepository _repository;

  Future<BookSlotResult> book({
    required int slotId,
    required bool optIn,
  }) async {
    final result = await _repository.reserveAndPay(
      slotId: slotId,
      whatsappOptIn: optIn,
    );

    return result.fold(
      (failure) {
        final status = _statusForFailure(failure);
        return BookSlotResult(
          status: status,
          message: failure.message.isNotEmpty ? failure.message : _messageFor(status),
        );
      },
      (session) => BookSlotResult(
        status: BookSlotStatus.success,
        booking: session.booking,
      ),
    );
  }

  Future<Either<Failure, BookingCheckoutSession>> reserveAndPay({
    required int slotId,
    bool whatsappOptIn = false,
  }) {
    return _repository.reserveAndPay(
      slotId: slotId,
      whatsappOptIn: whatsappOptIn,
    );
  }

  BookSlotStatus _statusForFailure(Failure failure) {
    final msg = failure.message.toUpperCase();
    if (msg.contains('SLOT_UNAVAILABLE')) return BookSlotStatus.slotUnavailable;
    if (msg.contains('SLOT_FULL')) return BookSlotStatus.slotFull;
    if (msg.contains('ALREADY_BOOKED')) return BookSlotStatus.alreadyBooked;
    if (msg.contains('TOO_MANY')) return BookSlotStatus.tooManyActive;
    return BookSlotStatus.unknown;
  }

  String _messageFor(BookSlotStatus status) => switch (status) {
    BookSlotStatus.slotUnavailable => AppStrings.slotUnavailable,
    BookSlotStatus.slotFull => AppStrings.slotFull,
    BookSlotStatus.alreadyBooked => AppStrings.alreadyBooked,
    BookSlotStatus.tooManyActive => AppStrings.tooManyActive,
    _ => AppStrings.bookingFailed,
  };
}
