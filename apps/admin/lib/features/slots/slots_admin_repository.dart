import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/result.dart';

/// Typed seam for slot administration (US6).
class SlotsAdminRepository {
  SlotsAdminRepository(this._db);
  final SupabaseClient _db;

  Future<Either<Failure, List<Map<String, dynamic>>>> list() async {
    try {
      final rows = ((await _db.from('service_slots').select()) as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      return Right(rows);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }

  Future<Either<Failure, void>> closeSlot(int slotId) async {
    try {
      await _db
          .from('service_slots')
          .update({'status': 'CLOSED'})
          .eq('id', slotId);
      return const Right(null);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }
}
