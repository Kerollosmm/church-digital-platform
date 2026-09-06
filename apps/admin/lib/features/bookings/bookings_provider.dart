import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Typed gateway seam for the bookings queue (US6): realtime subscription +
/// queue actions behind one small interface so widgets never touch the
/// transport directly.
abstract class BookingsGateway {
  Future<List<Map<String, dynamic>>> loadBookings({String? status});
  Future<void> confirmBooking(int bookingId);
  Future<void> completeBooking(int bookingId);
  Future<void> cancelBooking(int bookingId);

  /// Registers [onChange] for any bookings/service_slots change; returns an
  /// unsubscribe function.
  void Function() subscribeChanges(void Function() onChange);
}

class SupabaseBookingsGateway implements BookingsGateway {
  SupabaseBookingsGateway(this._db);
  final SupabaseClient _db;
  RealtimeChannel? _channel;

  @override
  Future<List<Map<String, dynamic>>> loadBookings({String? status}) async {
    var q = _db.from('bookings').select();
    if (status != null) {
      q = q.eq('status', status);
    }
    final rows =
        (await (q as dynamic).order('created_at', ascending: false)) as List;
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  @override
  Future<void> confirmBooking(int bookingId) =>
      _bookingRpc('confirm_booking', bookingId);
  @override
  Future<void> completeBooking(int bookingId) =>
      _bookingRpc('complete_booking', bookingId);
  @override
  Future<void> cancelBooking(int bookingId) =>
      _bookingRpc('cancel_booking', bookingId);

  Future<void> _bookingRpc(String fn, int bookingId) async {
    await _db.rpc(fn, params: {'p_booking_id': bookingId});
  }

  @override
  void Function() subscribeChanges(void Function() onChange) {
    try {
      if (!_db.realtime.isConnected) {
        return () {};
      }
      final channel = _db.channel('bookings_realtime');
      _channel = channel;
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'bookings',
            callback: (payload) => onChange(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'service_slots',
            callback: (payload) => onChange(),
          )
          .subscribe();
    } catch (e, st) {
      debugPrint('Realtime subscribe error: $e\n$st');
    }
    return () {
      final ch = _channel;
      if (ch != null) {
        ch.unsubscribe();
        _channel = null;
      }
    };
  }
}

const Object _unsetFilter = Object();

class BookingsState {
  final List<Map<String, dynamic>> bookings;
  final bool isLoading;
  final String? filter;
  final String? error;

  const BookingsState({
    this.bookings = const [],
    this.isLoading = true,
    this.filter,
    this.error,
  });

  BookingsState copyWith({
    List<Map<String, dynamic>>? bookings,
    bool? isLoading,
    Object? filter = _unsetFilter,
    String? error,
  }) {
    return BookingsState(
      bookings: bookings ?? this.bookings,
      isLoading: isLoading ?? this.isLoading,
      filter: filter == _unsetFilter ? this.filter : filter as String?,
      error: error ?? this.error,
    );
  }
}

class BookingsFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setFilter(String? filter) {
    state = filter;
  }
}

final bookingsFilterProvider =
    NotifierProvider<BookingsFilterNotifier, String?>(
      BookingsFilterNotifier.new,
    );

class BookingsNotifier extends Notifier<BookingsState> {
  BookingsNotifier(this._gateway);

  final BookingsGateway _gateway;
  void Function()? _unsubscribe;

  @override
  BookingsState build() {
    final filter = ref.watch(bookingsFilterProvider);

    _unsubscribe = _gateway.subscribeChanges(() => _loadBookings(state.filter));
    ref.onDispose(() {
      _unsubscribe?.call();
    });

    _loadBookings(filter);
    return BookingsState(isLoading: true, filter: filter);
  }

  Future<void> _loadBookings(String? filter) async {
    try {
      final rows = await _gateway.loadBookings(status: filter);
      state = state.copyWith(
        bookings: rows,
        isLoading: false,
        filter: filter,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        filter: filter,
        error: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    await _loadBookings(state.filter);
  }

  Future<void> confirmBooking(int bookingId) async {
    await _gateway.confirmBooking(bookingId);
    await _loadBookings(state.filter);
  }

  Future<void> completeBooking(int bookingId) async {
    await _gateway.completeBooking(bookingId);
    await _loadBookings(state.filter);
  }

  Future<void> cancelBooking(int bookingId) async {
    await _gateway.cancelBooking(bookingId);
    await _loadBookings(state.filter);
  }
}

final bookingsProvider =
    NotifierProvider.family<BookingsNotifier, BookingsState, BookingsGateway>(
      (gateway) => BookingsNotifier(gateway),
    );
