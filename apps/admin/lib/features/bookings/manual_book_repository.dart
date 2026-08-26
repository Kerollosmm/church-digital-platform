import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/result.dart';

/// Typed seam for staff-created manual bookings (US6).
class ManualBookRepository {
  ManualBookRepository(this._db);
  final SupabaseClient _db;

  Future<Either<Failure, List<Map<String, dynamic>>>> availableSlots() async {
    try {
      final res = await _db
          .from('v_available_slots')
          .select()
          .eq('slot_status', 'AVAILABLE');
      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return Right(list);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }

  Future<Either<Failure, void>> manualBook({
    required int slotId,
    required String phone,
    required bool optIn,
    required String notes,
  }) async {
    try {
      await _db.rpc(
        'manual_book',
        params: {
          'p_slot_id': slotId,
          'p_phone': phone,
          'p_opt_in': optIn,
          'p_notes': notes,
        },
      );
      return const Right(null);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }
}
