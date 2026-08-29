import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/result.dart';
import 'sacramental_models.dart';

abstract interface class SacramentsAdminRepository {
  Future<Either<Failure, List<SacramentalRecord>>> fetchSacramentalRecords({
    String? sacramentTypeFilter,
    String? searchQuery,
  });

  Future<Either<Failure, SacramentalRecord>> issueSacramentalCertificate(
    IssueSacramentInput input,
  );

  Future<Either<Failure, void>> revokeCertificate({
    required String recordId,
    required String reason,
  });

  Future<Either<Failure, List<Map<String, dynamic>>>> fetchPriests();
}

class SupabaseSacramentsAdminRepository implements SacramentsAdminRepository {
  SupabaseSacramentsAdminRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<Either<Failure, List<SacramentalRecord>>> fetchSacramentalRecords({
    String? sacramentTypeFilter,
    String? searchQuery,
  }) async {
    try {
      var query = _client
          .from('sacramental_records')
          .select('*, priests(name)');

      if (sacramentTypeFilter != null &&
          sacramentTypeFilter.isNotEmpty &&
          sacramentTypeFilter != 'ALL') {
        query = query.eq('sacrament_type', sacramentTypeFilter);
      }

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        query = query.ilike('recipient_name_ar', '%${searchQuery.trim()}%');
      }

      final res = await query.order('created_at', ascending: false);
      final list = (res as List)
          .map((e) => SacramentalRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      return Right(list);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }

  @override
  Future<Either<Failure, SacramentalRecord>> issueSacramentalCertificate(
    IssueSacramentInput input,
  ) async {
    try {
      final res = await _client.rpc(
        'issue_sacramental_certificate',
        params: input.toRpcParams(),
      );

      final recordId = res is Map
          ? (res['record_id'] ?? res['id']) as String?
          : null;

      if (recordId == null) {
        return const Left(
          Failure(
            code: 'ISSUANCE_FAILED',
            message: 'Failed to obtain record ID',
          ),
        );
      }

      final recordRes = await _client
          .from('sacramental_records')
          .select('*, priests(name)')
          .eq('id', recordId)
          .single();

      return Right(SacramentalRecord.fromJson(recordRes));
    } catch (e) {
      return Left(Failure.from(e));
    }
  }

  @override
  Future<Either<Failure, void>> revokeCertificate({
    required String recordId,
    required String reason,
  }) async {
    try {
      await _client.rpc(
        'admin_revoke_certificate',
        params: {'p_record_id': recordId, 'p_reason': reason.trim()},
      );
      return const Right(null);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> fetchPriests() async {
    try {
      final res = await _client
          .from('priests')
          .select('id, name, rank, phone')
          .order('name', ascending: true);
      return Right(List<Map<String, dynamic>>.from(res as List));
    } catch (e) {
      return Left(Failure.from(e));
    }
  }
}
