import 'package:mobile/models/available_slot.dart';
import 'package:mobile/models/booking.dart';
import 'package:mobile/models/book_slot_result.dart';
import 'package:mobile/repositories/booking_repository.dart';
import 'package:mobile/repositories/videos_repository.dart';

class FakeBookingRepository implements BookingRepository {
  FakeBookingRepository({
    this.bookings = const [],
    this.services = const [],
    this.slots = const [],
  });
  List<Booking> bookings;
  List<Map<String, dynamic>> services;
  List<Map<String, dynamic>> slots;
  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> fetchServices() async {
    calls.add('fetchServices');
    return services;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSlotsForService(int serviceId) async {
    calls.add('fetchSlotsForService');
    return slots;
  }

  @override
  Future<List<Booking>> fetchMyBookings() async {
    calls.add('fetchMyBookings');
    return bookings;
  }

  @override
  Future<BookSlotResult> bookSlot({
    required int slotId,
    required bool optIn,
  }) async {
    calls.add('bookSlot');
    return BookSlotResult(
      status: BookSlotStatus.success,
      booking: bookings.isNotEmpty ? bookings.first : null,
    );
  }

  @override
  Future<Map<String, dynamic>?> createCheckout(int bookingId) async => null;
  @override
  Future<void> cancelBooking(int bookingId) async {
    calls.add('cancelBooking');
  }

  @override
  Future<void> confirmBooking(int bookingId) async {}
  @override
  Future<void> completeBooking(int bookingId) async {}
  @override
  Future<List<AvailableSlot>> fetchAvailableSlots() async => [];
}

final fakeBooking = Booking(
  id: 5,
  status: 'CONFIRMED',
  serviceName: 'قداس',
  paidAmount: 0,
);

class FakeVideosRepository implements VideosRepository {
  FakeVideosRepository({this.videos = const [], this.payment});
  final List<Map<String, dynamic>> videos;
  final Map<String, dynamic>? payment;
  final List<int> purchaseCalls = [];
  @override
  Future<List<Map<String, dynamic>>> fetchVideos() async => videos;
  @override
  Future<Map<String, dynamic>?> purchaseVideo(int videoId) async {
    purchaseCalls.add(videoId);
    return payment;
  }
}
