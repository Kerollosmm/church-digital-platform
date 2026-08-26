import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef Row = Map<String, dynamic>;
typedef RpcHandler = Future<Object?> Function(Map<String, dynamic> args);

/// Real SupabaseClient over an in-memory PostgREST simulation.
/// Repositories under test are the production classes — only the transport
/// is faked (AGENTS.md "Direct Repository Testing").
class MockSupabase {
  MockSupabase({
    Map<String, List<Map<String, dynamic>>>? tables,
    Map<String, RpcHandler>? rpc,
  }) : data = tables != null
           ? tables.map(
               (k, v) => MapEntry(
                 k,
                 v.map((r) => Map<String, dynamic>.from(r)).toList(),
               ),
             )
           : {},
       rpcHandlers = rpc ?? {};

  final Map<String, List<Row>> data;
  final Map<String, RpcHandler> rpcHandlers;
  final List<String> requestLog = [];
  int _nextId = 1000;

  SupabaseClient build() {
    return SupabaseClient(
      'https://mock.supabase.co',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJtb2NrIiwicm9sZSI6ImFub24iLCJleHAiOjE5MDAwMDAwMDB9.k',
      httpClient: MockClient(_handle),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  }

  Future<http.Response> _handle(http.Request req) async {
    final path = req.url.path;
    requestLog.add(path);

    if (path.contains('/rest/v1/rpc/')) {
      final fn = path.split('/rest/v1/rpc/').last;
      final handler = rpcHandlers[fn];
      if (handler == null) {
        return http.Response(
          '{"message":"function not found"}',
          404,
          request: req,
        );
      }
      final args = req.body.isEmpty
          ? <String, dynamic>{}
          : (jsonDecode(req.body) as Map<String, dynamic>);
      final result = await handler(args);
      return http.Response(
        jsonEncode(result),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
        request: req,
      );
    }

    if (!path.contains('/rest/v1/')) {
      return http.Response('Not Found', 404, request: req);
    }
    final table = path.split('/rest/v1/').last.split('?').first;
    final rows = data.putIfAbsent(table, () => []);
    final idFilter = _idEq(req.url.query);

    switch (req.method) {
      case 'GET':
        var out = rows;
        if (idFilter != null) {
          out = out.where((r) => r['id'] == idFilter).toList();
        }
        return http.Response(
          jsonEncode(out),
          200,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'content-range':
                '0-${out.isEmpty ? 0 : out.length - 1}/${out.length}',
          },
          request: req,
        );
      case 'POST':
        final body = jsonDecode(req.body.isEmpty ? '[]' : req.body);
        final added = <Row>[];
        for (final raw in (body is List ? body : [body])) {
          final row = Map<String, dynamic>.from(raw as Row);
          row.putIfAbsent('id', () => ++_nextId);
          rows.add(row);
          added.add(row);
        }
        return http.Response(
          jsonEncode(added),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: req,
        );
      case 'PATCH':
        final patch = Map<String, dynamic>.from(jsonDecode(req.body) as Row);
        for (final r in rows.where(
          (r) => idFilter == null || r['id'] == idFilter,
        )) {
          r.addAll(patch);
        }
        return http.Response('', 204, request: req);
      case 'DELETE':
        rows.removeWhere((r) => idFilter == null || r['id'] == idFilter);
        return http.Response('', 204, request: req);
      default:
        return http.Response('Method Not Allowed', 405, request: req);
    }
  }

  static int? _idEq(String query) {
    final m = RegExp(r'id=eq\.(\d+)').firstMatch(query);
    return m == null ? null : int.parse(m.group(1)!);
  }
}
