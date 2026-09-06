import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/result.dart';

/// Typed seam for static content administration: FAQ + social links (US6).
class ContentRepository {
  ContentRepository(this._db);
  final SupabaseClient _db;

  Future<Either<Failure, List<Map<String, dynamic>>>> faq() async {
    try {
      final rows = ((await _db.from('faq').select().order('position')) as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      return Right(rows);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }

  Future<Either<Failure, void>> createFaq(Map<String, dynamic> row) async {
    try {
      await _db.from('faq').insert(row);
      return const Right(null);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }

  Future<Either<Failure, void>> deleteFaq(int id) async {
    try {
      await _db.from('faq').delete().eq('id', id);
      return const Right(null);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }

  Future<Either<Failure, List<Map<String, dynamic>>>> socialLinks() async {
    try {
      final rows =
          ((await _db.from('social_links').select().order('position')) as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
      return Right(rows);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }

  Future<Either<Failure, void>> createSocialLink(
    Map<String, dynamic> row,
  ) async {
    try {
      await _db.from('social_links').insert(row);
      return const Right(null);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }

  Future<Either<Failure, void>> deleteSocialLink(int id) async {
    try {
      await _db.from('social_links').delete().eq('id', id);
      return const Right(null);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }
}
