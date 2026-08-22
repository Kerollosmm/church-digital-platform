import '../core/either.dart';
import '../core/failure.dart';
import '../models/booking.dart';
import '../repositories/booking_repository.dart';
import '../services/app_strings.dart';

class BookingFlowController {
  BookingFlowController(this._repository);
  final BookingRepository _repository;

  Future<Either<Failure, Booking>> reserveAndPay({
    required int slotId,
    bool whatsappOptIn = false,
  }) {
    return _repository.reserveAndPay(
      slotId: slotId,
      whatsappOptIn: whatsappOptIn,
    );
  }

  String localizedMessage(Failure failure) {
    final msg = failure.message.toUpperCase();
    if (msg.contains('SLOT_UNAVAILABLE')) return AppStrings.slotUnavailable;
    if (msg.contains('SLOT_FULL')) return AppStrings.slotFull;
    if (msg.contains('ALREADY_BOOKED')) return AppStrings.alreadyBooked;
    if (msg.contains('TOO_MANY')) return AppStrings.tooManyActive;
    if (failure is AuthFailure || msg.contains('AUTH_REQUIRED')) {
      return AppStrings.authExpired;
    }
    return AppStrings.bookingFailed;
  }
}
