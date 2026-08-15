import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  Future<List<Row>> catchError(Function onError, {bool Function(Object error)? test}) =>
      Future.value(_rows).catchError(onError, test: test);
  @override
  Future<R> then<R>(FutureOr<R> Function(List<Row> value) onValue, {Function? onError}) =>
      Future.value(_rows).then(onValue, onError: onError);
  @override
  Future<List<Row>> timeout(Duration timeLimit, {FutureOr<List<Row>> Function()? onTimeout}) =>
      Future.value(_rows).timeout(timeLimit, onTimeout: onTimeout);
  @override
  Future<List<Row>> whenComplete(FutureOr<void> Function() action) =>
      Future.value(_rows).whenComplete(action);
}

class FakeTable {
  FakeTable(this._rows);
  final List<Row> _rows;

  FakeQuery select([Object? cols]) => FakeQuery(_rows);
  Future<void> insert(Map<String, dynamic> row) async {
    _rows.add(row);
  }
  FakeUpdate update(Map<String, dynamic> vals) => FakeUpdate(_rows, vals);
  FakeDelete delete() => FakeDelete(_rows);
}

class FakeUpdate {
  FakeUpdate(this._rows, this._vals);
  final List<Row> _rows;
  final Map<String, dynamic> _vals;
  Future<void> eq(String col, Object? val) async {
    for (final r in _rows.where((r) => r[col] == val)) {
      r.addAll(_vals);
    }
  }
}

class FakeDelete {
  FakeDelete(this._rows);
  final List<Row> _rows;
  Future<void> eq(String col, Object? val) async {
    _rows.removeWhere((r) => r[col] == val);
  }
}

class FakeRealtimeChannel {
  FakeRealtimeChannel(this.name);
  final String name;
  final List<Map<String, dynamic>> postgresChangeListeners = [];
  bool isSubscribed = false;

  FakeRealtimeChannel onPostgresChanges({
    dynamic event,
    String? schema,
    String? table,
    String? filter,
    required void Function(dynamic payload) callback,
  }) {
    postgresChangeListeners.add({
      'event': event,
      'schema': schema,
      'table': table,
      'filter': filter,
      'callback': callback,
    });
    return this;
  }

  FakeRealtimeChannel subscribe([void Function(dynamic status, dynamic error)? callback]) {
    isSubscribed = true;
    callback?.call('SUBSCRIBED', null);
    return this;
  }

  Future<String> unsubscribe() async {
    isSubscribed = false;
    return 'ok';
  }

  void triggerPostgresChange(String table, [Map<String, dynamic>? payload]) {
    for (final listener in postgresChangeListeners) {
      if (listener['table'] == table || listener['table'] == null) {
        (listener['callback'] as Function)(payload ?? {});
      }
    }
  }
}

class FakeFunctions {
  final List<String> invokedFunctions = [];
  final Map<String, dynamic> functionResults = {};
  HttpMethod? lastMethod;
  Map<String, String>? lastQueryParameters;

  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    dynamic responseType,
    HttpMethod method = HttpMethod.post,
    Map<String, String>? queryParameters,
  }) async {
    invokedFunctions.add(functionName);
    lastMethod = method;
    lastQueryParameters = queryParameters;
    final data = functionResults[functionName] ?? {'status': 'success'};
    return FunctionResponse(data: data, status: 200);
  }
}

class FakeSupabase {
  FakeSupabase(this.data, {this.rpcResults = const {}});
  final Map<String, List<Row>> data;
  final Map<String, dynamic> rpcResults;
  final List<String> rpcCalls = [];
  final Map<String, Map<String, Object?>> rpcArgs = {};
  final List<FakeRealtimeChannel> channels = [];
  final FakeFunctions functions = FakeFunctions();
  Map<String, dynamic>? currentUser = {'id': 'u1'};
  FakeTable from(String table) => FakeTable(data[table] ?? []);
  Future<dynamic> rpc(String fn, [Map<String, Object?> args = const {}]) async {
    rpcCalls.add(fn);
    rpcArgs[fn] = args;
    if (rpcResults.containsKey(fn)) {
      final res = rpcResults[fn];
      if (res is Function) {
        return res(args);
      }
      return res;
    }
    return {'id': 42, 'rpc': fn, 'args': args};
  }
  FakeRealtimeChannel channel(String name) {
    final ch = FakeRealtimeChannel(name);
    channels.add(ch);
    return ch;
  }
  Future<String> removeChannel(dynamic channel) async {
    if (channel is FakeRealtimeChannel) {
      channels.remove(channel);
    }
    return 'ok';
  }
  dynamic get auth => {'currentUser': currentUser};
}


