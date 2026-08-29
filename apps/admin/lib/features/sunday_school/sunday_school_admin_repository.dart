import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/result.dart';
import 'sunday_school_models.dart';

abstract interface class SundaySchoolAdminRepository {
  Future<Either<Failure, List<SundaySchoolClassModel>>> fetchClasses();
  Future<Either<Failure, SundaySchoolClassModel>> createClass({
    required String nameAr,
    required String stage,
    int? gradeLevel,
    String? academicYear,
  });
  Future<Either<Failure, void>> updateClass({
    required String classId,
    required String nameAr,
    required String stage,
    int? gradeLevel,
    String? academicYear,
  });
  Future<Either<Failure, void>> deleteClass(String classId);

  Future<Either<Failure, List<SundaySchoolServantModel>>> fetchServants({
    String? classId,
  });
  Future<Either<Failure, void>> assignServant({
    required String classId,
    required String userId,
    required String role,
  });
  Future<Either<Failure, void>> removeServant(String servantAssignmentId);

  Future<Either<Failure, List<SundaySchoolStudentModel>>> fetchStudents({
    String? classId,
  });
  Future<Either<Failure, SundaySchoolStudentModel>> addStudent({
    required String classId,
    required String fullNameAr,
    DateTime? birthDate,
    String? phone,
    String? parentPhone,
    String? notes,
  });
  Future<Either<Failure, void>> updateStudent({
    required String studentId,
    required String fullNameAr,
    String? classId,
    DateTime? birthDate,
    String? phone,
    String? parentPhone,
    String? notes,
  });
  Future<Either<Failure, void>> deleteStudent(String studentId);

  Future<Either<Failure, List<SundaySchoolAttendanceModel>>>
  fetchAttendanceHistory({required String classId, DateTime? date});

  Future<Either<Failure, SundaySchoolAnalyticsModel>> fetchAnalytics();

  Future<Either<Failure, Map<String, dynamic>>> recordBulkAttendance({
    required String classId,
    required DateTime sessionDate,
    required List<Map<String, dynamic>> records,
    String? sessionTitle,
  });
}

class SupabaseSundaySchoolAdminRepository
    implements SundaySchoolAdminRepository {
  SupabaseSundaySchoolAdminRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<Either<Failure, List<SundaySchoolClassModel>>> fetchClasses() async {
    try {
      final res = await _client
          .from('sunday_school_classes')
          .select('*, sunday_school_servants(id), sunday_school_students(id)')
          .order('grade_level', ascending: true, nullsFirst: false);

      final list = (res as List<dynamic>).map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        final servantsList =
            map['sunday_school_servants'] as List<dynamic>? ?? [];
        final studentsList =
            map['sunday_school_students'] as List<dynamic>? ?? [];
        map['servants_count'] = servantsList.length;
        map['students_count'] = studentsList.length;
        return SundaySchoolClassModel.fromJson(map);
      }).toList();

      return Right(list);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, SundaySchoolClassModel>> createClass({
    required String nameAr,
    required String stage,
    int? gradeLevel,
    String? academicYear,
  }) async {
    try {
      final payload = {
        'name_ar': nameAr,
        'stage': stage,
        'grade_level': gradeLevel,
        'academic_year': academicYear ?? '2025-2026',
      };
      final res = await _client
          .from('sunday_school_classes')
          .insert(payload)
          .select()
          .single();

      return Right(SundaySchoolClassModel.fromJson(res));
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateClass({
    required String classId,
    required String nameAr,
    required String stage,
    int? gradeLevel,
    String? academicYear,
  }) async {
    try {
      final payload = {
        'name_ar': nameAr,
        'stage': stage,
        'grade_level': gradeLevel,
        'academic_year': academicYear ?? '2025-2026',
      };
      await _client
          .from('sunday_school_classes')
          .update(payload)
          .eq('id', classId);

      return const Right(null);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteClass(String classId) async {
    try {
      await _client.from('sunday_school_classes').delete().eq('id', classId);

      return const Right(null);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<SundaySchoolServantModel>>> fetchServants({
    String? classId,
  }) async {
    try {
      var query = _client
          .from('sunday_school_servants')
          .select('*, users(name, phone), sunday_school_classes(name_ar)');

      if (classId != null && classId.isNotEmpty) {
        query = query.eq('class_id', classId);
      }

      final res = await query.order('created_at', ascending: false);
      final list = (res as List<dynamic>)
          .map(
            (e) => SundaySchoolServantModel.fromJson(e as Map<String, dynamic>),
          )
          .toList();

      return Right(list);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> assignServant({
    required String classId,
    required String userId,
    required String role,
  }) async {
    try {
      await _client.from('sunday_school_servants').insert({
        'class_id': classId,
        'user_id': userId,
        'role': role,
        'is_active': true,
      });
      return const Right(null);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> removeServant(
    String servantAssignmentId,
  ) async {
    try {
      await _client
          .from('sunday_school_servants')
          .delete()
          .eq('id', servantAssignmentId);
      return const Right(null);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<SundaySchoolStudentModel>>> fetchStudents({
    String? classId,
  }) async {
    try {
      var query = _client
          .from('sunday_school_students')
          .select('*, sunday_school_classes(name_ar)');

      if (classId != null && classId.isNotEmpty) {
        query = query.eq('class_id', classId);
      }

      final res = await query.order('full_name_ar', ascending: true);
      final list = (res as List<dynamic>)
          .map(
            (e) => SundaySchoolStudentModel.fromJson(e as Map<String, dynamic>),
          )
          .toList();

      return Right(list);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, SundaySchoolStudentModel>> addStudent({
    required String classId,
    required String fullNameAr,
    DateTime? birthDate,
    String? phone,
    String? parentPhone,
    String? notes,
  }) async {
    try {
      final payload = {
        'class_id': classId,
        'full_name_ar': fullNameAr,
        'birth_date': birthDate?.toIso8601String().split('T').first,
        'phone': phone,
        'parent_phone': parentPhone,
        'notes': notes,
        'is_active': true,
      };

      final res = await _client
          .from('sunday_school_students')
          .insert(payload)
          .select()
          .single();

      return Right(SundaySchoolStudentModel.fromJson(res));
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateStudent({
    required String studentId,
    required String fullNameAr,
    String? classId,
    DateTime? birthDate,
    String? phone,
    String? parentPhone,
    String? notes,
  }) async {
    try {
      final payload = <String, dynamic>{
        'full_name_ar': fullNameAr,
        'birth_date': birthDate?.toIso8601String().split('T').first,
        'phone': phone,
        'parent_phone': parentPhone,
        'notes': notes,
      };
      if (classId != null) {
        payload['class_id'] = classId;
      }

      await _client
          .from('sunday_school_students')
          .update(payload)
          .eq('id', studentId);

      return const Right(null);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteStudent(String studentId) async {
    try {
      await _client.from('sunday_school_students').delete().eq('id', studentId);
      return const Right(null);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<SundaySchoolAttendanceModel>>>
  fetchAttendanceHistory({required String classId, DateTime? date}) async {
    try {
      var query = _client
          .from('sunday_school_attendance')
          .select('*, sunday_school_students(full_name_ar)')
          .eq('class_id', classId);

      if (date != null) {
        final dateStr = date.toIso8601String().split('T').first;
        query = query.eq('session_date', dateStr);
      }

      final res = await query.order('session_date', ascending: false);
      final list = (res as List<dynamic>)
          .map(
            (e) =>
                SundaySchoolAttendanceModel.fromJson(e as Map<String, dynamic>),
          )
          .toList();

      return Right(list);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, SundaySchoolAnalyticsModel>> fetchAnalytics() async {
    try {
      final classesRes = await _client
          .from('sunday_school_classes')
          .select('stage');
      final servantsRes = await _client
          .from('sunday_school_servants')
          .select('id');
      final studentsRes = await _client
          .from('sunday_school_students')
          .select('id');
      final attendanceRes = await _client
          .from('sunday_school_attendance')
          .select('status');

      final classesList = classesRes as List<dynamic>;
      final servantsList = servantsRes as List<dynamic>;
      final studentsList = studentsRes as List<dynamic>;
      final attendanceList = attendanceRes as List<dynamic>;

      final stageMap = <String, int>{};
      for (final c in classesList) {
        final stage = (c as Map)['stage'] as String? ?? 'GENERAL';
        stageMap[stage] = (stageMap[stage] ?? 0) + 1;
      }

      int presentCount = 0;
      for (final a in attendanceList) {
        if ((a as Map)['status'] == 'PRESENT') {
          presentCount++;
        }
      }
      final rate = attendanceList.isNotEmpty
          ? (presentCount / attendanceList.length) * 100
          : 0.0;

      final analytics = SundaySchoolAnalyticsModel(
        totalClasses: classesList.length,
        totalServants: servantsList.length,
        totalStudents: studentsList.length,
        averageAttendanceRate: rate,
        stageBreakdown: stageMap,
      );

      return Right(analytics);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> recordBulkAttendance({
    required String classId,
    required DateTime sessionDate,
    required List<Map<String, dynamic>> records,
    String? sessionTitle,
  }) async {
    try {
      final res = await _client.rpc(
        'record_bulk_attendance',
        params: {
          'p_class_id': classId,
          'p_session_date': sessionDate.toIso8601String().split('T').first,
          'p_records': records,
          'p_session_title': sessionTitle,
        },
      );
      return Right(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }
}
