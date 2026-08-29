import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/either.dart';
import '../../core/failure.dart';
import 'sunday_school_models.dart';

abstract interface class SundaySchoolRepository {
  Future<Either<Failure, List<SundaySchoolClass>>> fetchMyClasses();
  Future<Either<Failure, List<SundaySchoolStudent>>> fetchClassStudents(
    String classId,
  );
  Future<Either<Failure, Map<String, dynamic>>> recordBulkAttendance({
    required String classId,
    required DateTime sessionDate,
    required List<StudentAttendanceEntry> entries,
    String? sessionTitle,
  });
  Future<Either<Failure, List<OfflineAttendanceMutation>>> getOfflineQueue();
  Future<Either<Failure, void>> enqueueOfflineAttendance(
    OfflineAttendanceMutation mutation,
  );
  Future<Either<Failure, int>> syncOfflineQueue();
}

class SupabaseSundaySchoolRepository implements SundaySchoolRepository {
  SupabaseSundaySchoolRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final List<OfflineAttendanceMutation> _offlineQueue = [];

  @override
  Future<Either<Failure, List<SundaySchoolClass>>> fetchMyClasses() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        // Fallback: fetch all active classes if user is anonymous or testing
        final res = await _client
            .from('sunday_school_classes')
            .select()
            .order('name_ar');
        final list = (res as List<dynamic>)
            .map((e) => SundaySchoolClass.fromJson(e as Map<String, dynamic>))
            .toList();
        return Right(list);
      }

      // Fetch classes where user is assigned as servant
      final servantsRes = await _client
          .from('sunday_school_servants')
          .select('class_id, sunday_school_classes(*)')
          .eq('user_id', user.id)
          .eq('is_active', true);

      final list = <SundaySchoolClass>[];
      for (final item in servantsRes as List<dynamic>) {
        final classData =
            item['sunday_school_classes'] as Map<String, dynamic>?;
        if (classData != null) {
          list.add(SundaySchoolClass.fromJson(classData));
        }
      }

      // If user has no specific assignments, fetch all active classes
      if (list.isEmpty) {
        final res = await _client
            .from('sunday_school_classes')
            .select()
            .order('name_ar');
        final all = (res as List<dynamic>)
            .map((e) => SundaySchoolClass.fromJson(e as Map<String, dynamic>))
            .toList();
        return Right(all);
      }

      return Right(list);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<SundaySchoolStudent>>> fetchClassStudents(
    String classId,
  ) async {
    try {
      final res = await _client
          .from('sunday_school_students')
          .select()
          .eq('class_id', classId)
          .eq('is_active', true)
          .order('full_name_ar');

      final list = (res as List<dynamic>)
          .map((e) => SundaySchoolStudent.fromJson(e as Map<String, dynamic>))
          .toList();

      return Right(list);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> recordBulkAttendance({
    required String classId,
    required DateTime sessionDate,
    required List<StudentAttendanceEntry> entries,
    String? sessionTitle,
  }) async {
    final recordsJson = entries.map((e) => e.toJson()).toList();
    try {
      final res = await _client.rpc(
        'record_bulk_attendance',
        params: {
          'p_class_id': classId,
          'p_session_date': sessionDate.toIso8601String().split('T').first,
          'p_records': recordsJson,
          'p_session_title': sessionTitle,
        },
      );

      return Right(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      // Auto queue for offline sync on network / server failure
      final mutation = OfflineAttendanceMutation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        classId: classId,
        sessionDate: sessionDate,
        sessionTitle: sessionTitle,
        records: recordsJson,
        createdAt: DateTime.now(),
      );
      _offlineQueue.add(mutation);
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<OfflineAttendanceMutation>>>
  getOfflineQueue() async {
    return Right(List.unmodifiable(_offlineQueue));
  }

  @override
  Future<Either<Failure, void>> enqueueOfflineAttendance(
    OfflineAttendanceMutation mutation,
  ) async {
    _offlineQueue.add(mutation);
    return const Right(null);
  }

  @override
  Future<Either<Failure, int>> syncOfflineQueue() async {
    int syncedCount = 0;
    final List<OfflineAttendanceMutation> toRemove = [];

    for (final mutation in _offlineQueue) {
      try {
        await _client.rpc(
          'record_bulk_attendance',
          params: {
            'p_class_id': mutation.classId,
            'p_session_date': mutation.sessionDate
                .toIso8601String()
                .split('T')
                .first,
            'p_records': mutation.records,
            'p_session_title': mutation.sessionTitle,
          },
        );
        mutation.isSynced = true;
        toRemove.add(mutation);
        syncedCount++;
      } catch (_) {
        // Stop syncing on persistent error
        break;
      }
    }

    _offlineQueue.removeWhere((m) => toRemove.contains(m));
    return Right(syncedCount);
  }
}
