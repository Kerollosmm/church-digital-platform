import '../models/booking.dart';
import '../repositories/booking_repository.dart';

class DashboardController {
  DashboardController(this._repository);
  final BookingRepository _repository;
  Future<List<Booking>> load() => _repository.fetchMyBookings();
}
