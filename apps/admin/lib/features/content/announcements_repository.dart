import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/result.dart';

/// Typed seam for the announcements feature (US6).
class AnnouncementsRepository {
  AnnouncementsRepository(this._db);
  final SupabaseClient _db;

  Future<Either<Failure, List<Map<String, dynamic>>>> list() async {
    try {
      final rows = ((await _db.from('announcements').select()) as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      return Right(rows);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }

  Future<Either<Failure, void>> create({
    required String titleAr,
    required String bodyAr,
  }) async {
    try {
      await _db.from('announcements').insert({
        'title_ar': titleAr,
        'body_ar': bodyAr,
        'tenant_id': 1,
        'published_at': DateTime.now().toUtc().toIso8601String(),
      });
      return const Right(null);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }

  Future<Either<Failure, void>> delete(int id) async {
    try {
      await _db.from('announcements').delete().eq('id', id);
      return const Right(null);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }
}
