import 'dart:async';
import 'package:mobile/services/app_supabase.dart';

typedef Row = Map<String, dynamic>;

class FakeQuery implements Future<List<Row>> {
  FakeQuery(this._rows);
  final List<Row> _rows;

  FakeQuery select([Object? cols]) => this;
  FakeQuery eq(String col, Object? val) =>
      FakeQuery(_rows.where((r) => r[col] == val).toList());
  FakeQuery update(Map<String, dynamic> vals) {
    for (final r in _rows) {
      r.addAll(vals);
    }
    return this;
  }

  FakeQuery order(String col, {bool ascending = true}) {
    final rows = [..._rows]
      ..sort((a, b) {
        final valA = a[col] ?? '';
        final valB = b[col] ?? '';
        return (valA as Comparable).compareTo(valB);
      });
    return FakeQuery(ascending ? rows : rows.reversed.toList());
  }

  FakeQuery limit(int n) => FakeQuery(_rows.take(n).toList());
  Future<Row?> maybeSingle() async => _rows.isEmpty ? null : _rows.first;
  Future<Row> single() async {
    if (_rows.isEmpty) throw Exception('PGRST116');
    return _rows.first;
  }

  @override
  Stream<List<Row>> asStream() => Stream.value(_rows);
  @override
  Future<List<Row>> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) => Future.value(_rows).catchError(onError, test: test);
  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Row> value) onValue, {
    Function? onError,
  }) => Future.value(_rows).then(onValue, onError: onError);
  @override
  Future<List<Row>> timeout(
    Duration timeLimit, {
    FutureOr<List<Row>> Function()? onTimeout,
  }) => Future.value(_rows).timeout(timeLimit, onTimeout: onTimeout);
  @override
  Future<List<Row>> whenComplete(FutureOr<void> Function() action) =>
      Future.value(_rows).whenComplete(action);
}

class FakeAuth {
  FakeAuth(this.currentUser);
  final Map<String, dynamic>? currentUser;
}

class FakeSupabase implements AppSupabase {
  FakeSupabase(this.data);
  final Map<String, List<Row>> data;
  final List<String> rpcCalls = [];
  final Map<String, Map<String, Object?>> rpcArgs = {};
  Map<String, dynamic>? currentUser = {'id': 'u1'};

  FakeQuery from(String table) => FakeQuery(
    data[table] ??
        (table == 'v_my_bookings' ? data['bookings'] : null) ??
        const [],
  );

  @override
  Future<Row?> rpc(String fn, [Map<String, Object?> args = const {}]) async {
    rpcCalls.add(fn);
    rpcArgs[fn] = args;
    return {'id': 42, 'rpc': fn, 'args': args};
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String table, {
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
  }) async {
    var query = from(table);
    if (filters != null) {
      for (final entry in filters.entries) {
        query = query.eq(entry.key, entry.value);
      }
    }
    if (orderBy != null && orderBy.isNotEmpty) {
      query = query.order(orderBy, ascending: ascending);
    }
    return await query;
  }

  @override
  Future<Map<String, dynamic>> invokeFunction(
    String fn, {
    Map<String, dynamic>? body,
  }) async {
    rpcCalls.add(fn);
    if (body != null) rpcArgs[fn] = Map<String, Object?>.from(body);
    return {
      'checkout_url': 'https://paymob.com/checkout/test',
      'rpc': fn,
      'args': body,
    };
  }

  FakeAuth get auth => FakeAuth(currentUser);
}
