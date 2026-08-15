import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class VideosRepository {
  Future<List<Map<String, dynamic>>> fetchVideos();
  Future<Map<String, dynamic>?> purchaseVideo(int videoId);
}

class SupabaseVideosRepository implements VideosRepository {
  SupabaseVideosRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> fetchVideos() async {
    final res = await _client
        .from('videos')
        .select('id, title_ar, price, event_date, privacy, video_purchases(id, access_granted_at)')
        .order('event_date', ascending: false);
    return (res as List).map((r) {
      final map = Map<String, dynamic>.from(r as Map);
      final purchases = map['video_purchases'] as List?;
      final hasAccess = purchases != null &&
          purchases.isNotEmpty &&
          purchases.any((p) => p is Map && p['access_granted_at'] != null);
      map['is_purchased'] = hasAccess;
      return map;
    }).toList();
  }

  @override
  Future<Map<String, dynamic>?> purchaseVideo(int videoId) async {
    final data = await _client.rpc(
      'purchase_video',
      params: {'p_video_id': videoId},
    );
    if (data == null) return null;
    if (data is num) return {'id': data.toInt()};
    if (data is String) {
      final parsed = int.tryParse(data);
      return parsed != null ? {'id': parsed} : null;
    }
    if (data is Map) {
      final id = data['id'];
      if (id != null) return Map<String, dynamic>.from(data);
      return null;
    }
    final parsed = int.tryParse(data.toString());
    return parsed != null ? {'id': parsed} : null;
  }

}
