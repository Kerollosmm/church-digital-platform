import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


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

final bookingsFilterProvider = NotifierProvider<BookingsFilterNotifier, String?>(
  BookingsFilterNotifier.new,
);

class BookingsNotifier extends Notifier<BookingsState> {
  BookingsNotifier(this._db);

  final dynamic _db;
  dynamic _channel;

  @override
  BookingsState build() {
    final filter = ref.watch(bookingsFilterProvider);

    _subscribeRealtime();
    ref.onDispose(() {
      unawaited(_unsubscribeRealtime());
    });

    _loadBookings(filter);
    return BookingsState(isLoading: true, filter: filter);
  }

  void _subscribeRealtime() {
    try {
      final channel = _db.channel('bookings_realtime');
      _channel = channel;
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'bookings',
            callback: (payload) => _loadBookings(state.filter),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'service_slots',
            callback: (payload) => _loadBookings(state.filter),
          )
          .subscribe();
    } catch (e, st) {
      debugPrint('Realtime subscribe error: $e\n$st');
    }
  }

  Future<void> _unsubscribeRealtime() async {
    if (_channel != null) {
      try {
        await _channel.unsubscribe();
      } catch (e, st) {
        debugPrint('Realtime unsubscribe error: $e\n$st');
      }
      _channel = null;
    }
  }


  Future<void> _loadBookings(String? filter) async {
    try {
      var q = _db.from('bookings').select().order('created_at', ascending: false);
      if (filter != null) {
        q = q.eq('status', filter);
      }
      final res = await q;
      final rows = (res as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
      state = state.copyWith(bookings: rows, isLoading: false, filter: filter, error: null);
    } catch (e) {
      state = state.copyWith(isLoading: false, filter: filter, error: e.toString());
    }
  }

  Future<void> refresh() async {
    await _loadBookings(state.filter);
  }

  Future<void> executeRpc(String fn, int bookingId) async {
    await _db.rpc(fn, params: {'p_booking_id': bookingId});
    await _loadBookings(state.filter);
  }
}

final bookingsProvider = NotifierProvider.family<BookingsNotifier, BookingsState, dynamic>(
  (db) => BookingsNotifier(db),
);
