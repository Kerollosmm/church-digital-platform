import 'package:mobile/services/app_supabase.dart';

class TestAppSupabase implements AppSupabase {
  TestAppSupabase(
    this._rowsByTable, {
    Map<String, Future<Object?> Function(Map<String, dynamic>)>? rpcHandler,
  }) : rpcHandler = rpcHandler ?? const {};
  final Map<String, List<Map<String, dynamic>>> _rowsByTable;
  final Map<String, Future<Object?> Function(Map<String, dynamic>)> rpcHandler;
  final List<String> rpcCalls = [];
  final Map<String, Map<String, dynamic>> rpcArgs = {};

  @override
  Future<Object?> rpc(String fn, Map<String, dynamic> params) async {
    rpcCalls.add(fn);
    rpcArgs[fn] = params;
    final handler = rpcHandler[fn];
    if (handler == null) throw UnimplementedError('rpc $fn not stubbed');
    return handler(params);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String table, {
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
  }) async {
    var rows = List<Map<String, dynamic>>.from(
      _rowsByTable[table] ??
          (table == 'v_my_bookings' ? _rowsByTable['bookings'] : null) ??
          const [],
    );
    filters?.forEach((k, v) => rows = rows.where((r) => r[k] == v).toList());
    if (orderBy != null && orderBy.isNotEmpty) {
      rows.sort((a, b) => (a[orderBy] ?? '').compareTo(b[orderBy] ?? ''));
      if (!ascending) rows = rows.reversed.toList();
    }
    return rows;
  }

  @override
  Future<Map<String, dynamic>> invokeFunction(
    String fn, {
    Map<String, dynamic>? body,
  }) async {
    rpcCalls.add(fn);
    if (body != null) rpcArgs[fn] = body;
    final handler = rpcHandler[fn];
    if (handler != null) {
      final res = await handler(body ?? {});
      if (res is Map) return Map<String, dynamic>.from(res);
    }
    return {'fn': fn, 'body': body};
  }

  @override
  Future<String> uploadStorage(
    String bucket,
    String path,
    List<int> bytes, {
    String? contentType,
  }) async {
    rpcCalls.add('uploadStorage:$bucket/$path');
    return path;
  }

  @override
  Future<void> deleteStorage(String bucket, String path) async {
    rpcCalls.add('deleteStorage:$bucket/$path');
  }
}
