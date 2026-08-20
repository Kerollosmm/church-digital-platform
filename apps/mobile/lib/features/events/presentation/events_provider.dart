import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/event_booking_repository.dart';
import '../domain/event_models.dart';

class EventBookingState {
  final EventTypeModel? selectedEventType;
  final DateTime? requestedTime;
  final Map<int, SelectedExtraService> selectedExtras;
  final String? notes;
  final bool isSubmitting;
  final String? error;
  final int? createdBookingId;

  const EventBookingState({
    this.selectedEventType,
    this.requestedTime,
    this.selectedExtras = const {},
    this.notes,
    this.isSubmitting = false,
    this.error,
    this.createdBookingId,
  });

  EventBookingState copyWith({
    EventTypeModel? selectedEventType,
    DateTime? requestedTime,
    Map<int, SelectedExtraService>? selectedExtras,
    String? notes,
    bool? isSubmitting,
    String? error,
    int? createdBookingId,
  }) {
    return EventBookingState(
      selectedEventType: selectedEventType ?? this.selectedEventType,
      requestedTime: requestedTime ?? this.requestedTime,
      selectedExtras: selectedExtras ?? this.selectedExtras,
      notes: notes ?? this.notes,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      createdBookingId: createdBookingId ?? this.createdBookingId,
    );
  }

  int get basePricePiastres => selectedEventType?.basePricePiastres ?? 0;
  int get extrasTotalPiastres =>
      selectedExtras.values.fold(0, (sum, item) => sum + item.totalPricePiastres);
  int get grandTotalPiastres => basePricePiastres + extrasTotalPiastres;

  double get grandTotalEgp => grandTotalPiastres / 100.0;
}

class EventBookingNotifier extends Notifier<EventBookingState> {
  late final EventBookingRepository _repo;

  @override
  EventBookingState build() {
    _repo = ref.watch(eventBookingRepositoryProvider);
    return const EventBookingState();
  }

  void selectEventType(EventTypeModel type) {
    state = state.copyWith(selectedEventType: type);
  }

  void setRequestedTime(DateTime time) {
    state = state.copyWith(requestedTime: time);
  }

  void toggleExtra(ExtraServiceModel extra, bool isSelected) {
    final updated = Map<int, SelectedExtraService>.from(state.selectedExtras);
    if (isSelected) {
      updated[extra.id] = SelectedExtraService(service: extra, quantity: 1);
    } else {
      updated.remove(extra.id);
    }
    state = state.copyWith(selectedExtras: updated);
  }

  void updateExtraQuantity(ExtraServiceModel extra, int quantity) {
    if (quantity <= 0) {
      toggleExtra(extra, false);
      return;
    }
    final updated = Map<int, SelectedExtraService>.from(state.selectedExtras);
    updated[extra.id] = SelectedExtraService(service: extra, quantity: quantity);
    state = state.copyWith(selectedExtras: updated);
  }

  void setNotes(String notes) {
    state = state.copyWith(notes: notes);
  }

  Future<int?> submitBooking() async {
    if (state.selectedEventType == null || state.requestedTime == null) {
      state = state.copyWith(error: 'يرجى اختيار نوع المناسبة والموعد المطلوب');
      return null;
    }

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final bookingId = await _repo.submitEventBooking(
        eventTypeId: state.selectedEventType!.id,
        requestedTime: state.requestedTime!,
        extras: state.selectedExtras.values.toList(),
        notes: state.notes,
      );
      state = state.copyWith(isSubmitting: false, createdBookingId: bookingId);
      return bookingId;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return null;
    }
  }
}

final eventBookingNotifierProvider =
    NotifierProvider<EventBookingNotifier, EventBookingState>(EventBookingNotifier.new);

final eventTypesProvider = FutureProvider<List<EventTypeModel>>((ref) async {
  return ref.watch(eventBookingRepositoryProvider).fetchEventTypes();
});

final extraServicesProvider = FutureProvider<List<ExtraServiceModel>>((ref) async {
  return ref.watch(eventBookingRepositoryProvider).fetchExtraServices();
});

final myEventBookingsProvider = FutureProvider<List<EventBookingModel>>((ref) async {
  return ref.watch(eventBookingRepositoryProvider).fetchMyEventBookings();
});
