import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class VideosRepository {
  Future<List<Map<String, dynamic>>> fetchVideos();
  Future<Map<String, dynamic>?> purchaseVideo(int videoId);
}

class SupabaseVideosRepository implements VideosRepository {
  SupabaseVideosRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> fetchVideos() async =>
      ((await _client
                  .from('videos')
                  .select('id, title_ar, price, event_date, privacy')
                  .order('event_date', ascending: false))
              as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

  @override
  Future<Map<String, dynamic>?> purchaseVideo(int videoId) async {
    final data = await _client.rpc(
      'purchase_video',
      params: {'p_video_id': videoId},
    );
    return data == null ? null : Map<String, dynamic>.from(data as Map);
  }
}
