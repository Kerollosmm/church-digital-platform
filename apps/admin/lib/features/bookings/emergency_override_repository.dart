import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/result.dart';

/// Typed seam for emergency slot overrides (US6).
class EmergencyOverrideRepository {
  EmergencyOverrideRepository(this._db);
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

  Future<Either<Failure, void>> override({
    required int bookingId,
    required int newSlotId,
    required bool refund,
  }) async {
    try {
      await _db.rpc('emergency_override', params: {
        'p_booking_id': bookingId,
        'p_new_slot_id': newSlotId,
        'p_refund': refund,
      });
      return const Right(null);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }
}
