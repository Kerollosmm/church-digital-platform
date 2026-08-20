import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/admin_event_repository.dart';
import '../domain/admin_event_models.dart';

class AdminEventFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setFilter(String? filter) {
    state = filter;
  }
}

final adminEventFilterProvider =
    NotifierProvider<AdminEventFilterNotifier, String?>(AdminEventFilterNotifier.new);

final eventQueueProvider = FutureProvider<List<AdminEventBookingModel>>((ref) async {
  final filter = ref.watch(adminEventFilterProvider);
  return ref.watch(adminEventRepositoryProvider).fetchEventBookingsQueue(statusFilter: filter);
});

final venuesProvider = FutureProvider<List<VenueResourceModel>>((ref) async {
  return ref.watch(adminEventRepositoryProvider).fetchVenues();
});
