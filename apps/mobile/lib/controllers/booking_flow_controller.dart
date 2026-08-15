import '../models/book_slot_result.dart';
import '../repositories/booking_repository.dart';
import '../services/app_strings.dart';

class BookingFlowController {
  BookingFlowController(this._repository);
  final BookingRepository _repository;

  Future<BookSlotResult> book({
    required int slotId,
    required bool optIn,
  }) async {
    final result = await _repository.bookSlot(slotId: slotId, optIn: optIn);
    if (result.status == BookSlotStatus.success) return result;
    return BookSlotResult(
      status: result.status,
      message: _messageFor(result.status),
      booking: result.booking,
    );
  }

  String _messageFor(BookSlotStatus status) => switch (status) {
    BookSlotStatus.slotUnavailable => AppStrings.slotUnavailable,
    BookSlotStatus.slotFull => AppStrings.slotFull,
    BookSlotStatus.alreadyBooked => AppStrings.alreadyBooked,
    BookSlotStatus.tooManyActive => AppStrings.tooManyActive,
    _ => AppStrings.bookingFailed,
  };
}
