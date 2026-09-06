import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/result.dart';
import 'models/payment_proof_review.dart';
import 'models/payout_channel.dart';

/// Typed seam for the payments ledger and manual payment proof verification.
class PaymentsAdminRepository {
  PaymentsAdminRepository(this._db);
  final SupabaseClient _db;

  Future<Either<Failure, List<Map<String, dynamic>>>> list() async {
    try {
      final rows =
          ((await _db
                      .from('payments')
                      .select()
                      .order('created_at', ascending: false))
                  as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
      return Right(rows);
    } catch (e) {
      return Left(_mapFailure(e));
    }
  }

  Future<Either<Failure, List<PaymentProofReview>>> listPendingProofs() async {
    try {
      final rows =
          ((await _db
                      .from('payment_proofs')
                      .select()
                      .eq('status', 'PENDING')
                      .order('created_at', ascending: true))
                  as List)
              .map(
                (r) => PaymentProofReview.fromJson(
                  Map<String, dynamic>.from(r as Map),
                ),
              )
              .toList();
      return Right(rows);
    } catch (e) {
      return Left(_mapFailure(e));
    }
  }

  Future<Either<Failure, void>> approveProof(
    int proofId, {
    String? collectorNote,
  }) async {
    try {
      await _db.rpc(
        'approve_payment_proof',
        params: {'p_proof_id': proofId, 'p_collector_note': collectorNote},
      );
      return const Right(null);
    } catch (e) {
      return Left(_mapFailure(e));
    }
  }

  Future<Either<Failure, void>> rejectProof(
    int proofId,
    String reasonCode,
  ) async {
    try {
      await _db.rpc(
        'reject_payment_proof',
        params: {'p_proof_id': proofId, 'p_reason_code': reasonCode},
      );
      return const Right(null);
    } catch (e) {
      return Left(_mapFailure(e));
    }
  }

  Future<Either<Failure, List<PayoutChannel>>> listPayoutChannels() async {
    try {
      final rows =
          ((await _db
                      .from('payout_channels')
                      .select()
                      .order('id', ascending: true))
                  as List)
              .map(
                (r) =>
                    PayoutChannel.fromJson(Map<String, dynamic>.from(r as Map)),
              )
              .toList();
      return Right(rows);
    } catch (e) {
      return Left(_mapFailure(e));
    }
  }

  Future<Either<Failure, void>> upsertPayoutChannel(PayoutChannel c) async {
    try {
      await _db
          .from('payout_channels')
          .update({
            'display_name_ar': c.displayNameAr,
            'account_number': c.accountNumber,
            'holder_name': c.holderName,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('channel', c.channel);
      return const Right(null);
    } catch (e) {
      return Left(_mapFailure(e));
    }
  }

  Future<Either<Failure, void>> markCashReceived(
    int bookingId,
    int amount, {
    String? collectorNote,
  }) async {
    try {
      await _db.rpc(
        'mark_cash_received',
        params: {
          'p_booking_id': bookingId,
          'p_amount': amount,
          'p_collector_note': collectorNote,
        },
      );
      return const Right(null);
    } catch (e) {
      return Left(_mapFailure(e));
    }
  }

  Failure _mapFailure(Object e) {
    if (e is PostgrestException) {
      if (e.code == '42501') {
        return const Failure(
          code: 'FORBIDDEN',
          message: 'ليس لديك صلاحية لتنفيذ هذا الإجراء',
        );
      }
      if (e.code == '28000') {
        return const Failure(
          code: 'UNAUTHORIZED',
          message: 'يرجى تسجيل الدخول أولاً',
        );
      }
      return Failure(code: e.code ?? 'BAD_REQUEST', message: e.message);
    }
    return Failure.from(e);
  }
}
