import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/result.dart';

/// Typed seam for the complaints desk (US6).
class ComplaintsAdminRepository {
  ComplaintsAdminRepository(this._db);
  final SupabaseClient _db;

  Future<Either<Failure, List<Map<String, dynamic>>>> list() async {
    try {
      final res = await _db
          .from('v_complaints')
          .select()
          .order('created_at', ascending: false);
      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return Right(list);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }

  Future<Either<Failure, String>> decrypt(int complaintId) async {
    try {
      final res = await _db.rpc(
        'decrypt_complaint',
        params: {'p_complaint_id': complaintId},
      );
      final decryptedText = res is Map
          ? (res['decrypted'] ?? res.toString())
          : res.toString();
      return Right(decryptedText as String);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }
}
