import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/result.dart';

/// Typed seam for analytics read models (US6). One reader per view.
class AnalyticsRepository {
  AnalyticsRepository(this._db);
  final dynamic _db;

  Future<Either<Failure, List<Map<String, dynamic>>>> bookingRows() =>
      _readView('v_analytics_bookings');

  Future<Either<Failure, List<Map<String, dynamic>>>> paymentRows() =>
      _readView('v_analytics_payments');

  Future<Either<Failure, List<Map<String, dynamic>>>> utilizationRows() =>
      _readView('v_analytics_utilization');

  Future<Either<Failure, String>> exportPaymentsCsv() async {
    try {
      final res = await _db.functions.invoke(
        'analytics-export',
        method: HttpMethod.get,
        queryParameters: const {'report': 'payments'},
      );
      if (res.status != 200) {
        return Left(Failure(code: 'INTERNAL', message: 'فشل تصدير التقرير (رمز ${res.status})'));
      }
      return Right(res.data?.toString() ?? '');
    } catch (_) {
      return const Left(Failure(code: 'INTERNAL', message: 'فشل تصدير التقرير'));
    }
  }

  Future<Either<Failure, List<Map<String, dynamic>>>> _readView(
    String view,
  ) async {
    try {
      final res = await _db.from(view).select();
      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return Right(list);
    } catch (e) {
      return Left(Failure.from(e));
    }
  }
}
