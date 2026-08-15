import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AppSupabase {
  Future<Object?> rpc(String fn, Map<String, dynamic> params);
  Future<List<Map<String, dynamic>>> query(
    String table, {
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
  });
  Future<Map<String, dynamic>> invokeFunction(
    String fn, {
    Map<String, dynamic>? body,
  });
}

class SupabaseAppSupabase implements AppSupabase {
  SupabaseAppSupabase(this._client);
  final SupabaseClient _client;

  @override
  Future<Object?> rpc(String fn, Map<String, dynamic> params) async =>
      await _client.rpc(fn, params: params);

  @override
  Future<List<Map<String, dynamic>>> query(
    String table, {
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
  }) async {
    PostgrestTransformBuilder<List<Map<String, dynamic>>> builder = _client
        .from(table)
        .select()
        .match(Map<String, Object>.from(filters ?? const {}));
    if (orderBy != null && orderBy.isNotEmpty) {
      builder = builder.order(orderBy, ascending: ascending);
    }
    final res = await builder;
    return res.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  @override
  Future<Map<String, dynamic>> invokeFunction(
    String fn, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _client.functions.invoke(fn, body: body);
    if (response.status != 200) {
      throw Exception(
        'Function $fn failed with status ${response.status}: ${response.data}',
      );
    }
    return Map<String, dynamic>.from(response.data as Map);
  }
}

class UnimplementedAppSupabase implements AppSupabase {
  @override
  Future<Object?> rpc(String fn, Map<String, dynamic> params) =>
      throw UnimplementedError('rpc $fn called in test dependencies');
  @override
  Future<List<Map<String, dynamic>>> query(
    String table, {
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
  }) => throw UnimplementedError('query $table called in test dependencies');
  @override
  Future<Map<String, dynamic>> invokeFunction(
    String fn, {
    Map<String, dynamic>? body,
  }) => throw UnimplementedError(
    'invokeFunction $fn called in test dependencies',
  );
}
