import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/repositories/videos_repository.dart';

class MockRpcSupabaseClient {
  MockRpcSupabaseClient(this.rpcResult);
  final dynamic rpcResult;
  String? lastFunction;
  Map<String, dynamic>? lastParams;

  dynamic rpc(String fn, {Map<String, dynamic>? params}) {
    lastFunction = fn;
    lastParams = params;
    return Future.value(rpcResult);
  }
}

void main() {
  group('SupabaseVideosRepository.purchaseVideo RPC result parsing', () {
    test('parses numeric ID returned from RPC', () async {
      final client = MockRpcSupabaseClient(42);
      final repo = SupabaseVideosRepository(client);

      final result = await repo.purchaseVideo(10);
      expect(result, equals({'id': 42}));
      expect(client.lastFunction, equals('purchase_video'));
      expect(client.lastParams, equals({'p_video_id': 10}));
    });

    test('parses numeric string ID returned from RPC', () async {
      final client = MockRpcSupabaseClient('123');
      final repo = SupabaseVideosRepository(client);

      final result = await repo.purchaseVideo(10);
      expect(result, equals({'id': 123}));
    });

    test('parses Map containing valid numeric ID from RPC', () async {
      final client = MockRpcSupabaseClient({'id': 50, 'status': 'CREATED'});
      final repo = SupabaseVideosRepository(client);

      final result = await repo.purchaseVideo(10);
      expect(result, equals({'id': 50, 'status': 'CREATED'}));
    });

    test('returns null when Map contains null id', () async {
      final client = MockRpcSupabaseClient({'id': null});
      final repo = SupabaseVideosRepository(client);

      final result = await repo.purchaseVideo(10);
      expect(result, isNull);
    });

    test('returns null when RPC returns unparsable string', () async {
      final client = MockRpcSupabaseClient('not-a-valid-number');
      final repo = SupabaseVideosRepository(client);

      final result = await repo.purchaseVideo(10);
      expect(result, isNull);
    });

    test('returns null when RPC returns null', () async {
      final client = MockRpcSupabaseClient(null);
      final repo = SupabaseVideosRepository(client);

      final result = await repo.purchaseVideo(10);
      expect(result, isNull);
    });

    test('returns null when RPC returns arbitrary unparsable object', () async {
      final client = MockRpcSupabaseClient(Object());
      final repo = SupabaseVideosRepository(client);

      final result = await repo.purchaseVideo(10);
      expect(result, isNull);
    });
  });
}
