import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/result.dart';

/// Typed seam for the payments ledger read model (US6).
class PaymentsAdminRepository {
  PaymentsAdminRepository(this._db);
  final SupabaseClient _db;

  Future<Either<Failure, List<Map<String, dynamic>>>> list() async {
    try {
      final rows = ((await _db
              .from('payments')
              .select()
              .order('created_at', ascending: false)) as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      return Right(rows);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }
}
