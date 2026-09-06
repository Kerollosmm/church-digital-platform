import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/either.dart';
import '../../core/failure.dart';
import 'sacramental_models.dart';

abstract interface class SacramentalRecordsRepository {
  Future<Either<Failure, List<SacramentalRecord>>> getMyCertificates();
  Future<Either<Failure, CertificateVerificationResult>> verifyCertificate(
    String token,
  );
  Future<Either<Failure, String>> getCertificateSignedUrl(
    String pdfStoragePath,
  );
}

class SupabaseSacramentalRecordsRepository
    implements SacramentalRecordsRepository {
  SupabaseSacramentalRecordsRepository({this.client});

  final SupabaseClient? client;
  SupabaseClient get _db => client ?? Supabase.instance.client;

  @override
  Future<Either<Failure, List<SacramentalRecord>>> getMyCertificates() async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) {
        return const Left(AuthFailure('يجب تسجيل الدخول لعرض الشهادات'));
      }

      final res = await _db
          .from('sacramental_records')
          .select('*, priests(name)')
          .eq('recipient_user_id', user.id)
          .order('sacrament_date', ascending: false);

      final list = (res as List<dynamic>)
          .map((e) => SacramentalRecord.fromJson(e as Map<String, dynamic>))
          .toList();

      return Right(list);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, CertificateVerificationResult>> verifyCertificate(
    String token,
  ) async {
    try {
      final res = await _db.rpc(
        'verify_certificate',
        params: {'p_token': token.trim()},
      );

      if (res is Map<String, dynamic>) {
        return Right(CertificateVerificationResult.fromJson(res));
      } else if (res is Map) {
        return Right(
          CertificateVerificationResult.fromJson(
            Map<String, dynamic>.from(res),
          ),
        );
      }
      return const Left(ServerFailure('استجابة غير متوقعة من خادم التحقق'));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, String>> getCertificateSignedUrl(
    String pdfStoragePath,
  ) async {
    try {
      final cleanPath = pdfStoragePath.startsWith('certificates/')
          ? pdfStoragePath.replaceFirst('certificates/', '')
          : pdfStoragePath;

      final url = await _db.storage
          .from('certificates')
          .createSignedUrl(cleanPath, 3600);

      return Right(url);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
