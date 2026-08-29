import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/core/result.dart';
import 'package:admin/features/sunday_school/sunday_school_admin_dashboard.dart';
import 'package:admin/features/sunday_school/sunday_school_admin_repository.dart';
import 'package:admin/features/sunday_school/sunday_school_models.dart';
import '../../helpers/mock_supabase.dart';

class FakeSundaySchoolAdminRepository implements SundaySchoolAdminRepository {
  final List<SundaySchoolClassModel> classes = [
    const SundaySchoolClassModel(
      id: 'c-1',
      nameAr: 'فصل داود - رابعة ابتدائي',
      stage: 'PRIMARY',
      gradeLevel: 4,
      academicYear: '2025-2026',
      servantsCount: 2,
      studentsCount: 15,
    ),
  ];

  final List<SundaySchoolServantModel> servants = [
    const SundaySchoolServantModel(
      id: 's-1',
      classId: 'c-1',
      userId: 'u-1',
      role: 'LEADER',
      userName: 'الخادم مينا',
      userPhone: '+201011112222',
      classNameAr: 'فصل داود - رابعة ابتدائي',
    ),
  ];

  final List<SundaySchoolStudentModel> students = [
    const SundaySchoolStudentModel(
      id: 'st-1',
      classId: 'c-1',
      fullNameAr: 'كيرلس مينا',
      parentPhone: '+201099998888',
      classNameAr: 'فصل داود - رابعة ابتدائي',
    ),
  ];

  @override
  Future<Either<Failure, List<SundaySchoolClassModel>>> fetchClasses() async =>
      Right(classes);

  @override
  Future<Either<Failure, SundaySchoolClassModel>> createClass({
    required String nameAr,
    required String stage,
    int? gradeLevel,
    String? academicYear,
  }) async {
    final newClass = SundaySchoolClassModel(
      id: 'c-${classes.length + 1}',
      nameAr: nameAr,
      stage: stage,
      gradeLevel: gradeLevel,
      academicYear: academicYear ?? '2025-2026',
    );
    classes.add(newClass);
    return Right(newClass);
  }

  @override
  Future<Either<Failure, void>> updateClass({
    required String classId,
    required String nameAr,
    required String stage,
    int? gradeLevel,
    String? academicYear,
  }) async => const Right(null);

  @override
  Future<Either<Failure, void>> deleteClass(String classId) async {
    classes.removeWhere((c) => c.id == classId);
    return const Right(null);
  }

  @override
  Future<Either<Failure, List<SundaySchoolServantModel>>> fetchServants({
    String? classId,
  }) async => Right(servants);

  @override
  Future<Either<Failure, void>> assignServant({
    required String classId,
    required String userId,
    required String role,
  }) async => const Right(null);

  @override
  Future<Either<Failure, void>> removeServant(
    String servantAssignmentId,
  ) async => const Right(null);

  @override
  Future<Either<Failure, List<SundaySchoolStudentModel>>> fetchStudents({
    String? classId,
  }) async => Right(students);

  @override
  Future<Either<Failure, SundaySchoolStudentModel>> addStudent({
    required String classId,
    required String fullNameAr,
    DateTime? birthDate,
    String? phone,
    String? parentPhone,
    String? notes,
  }) async {
    final s = SundaySchoolStudentModel(
      id: 'st-${students.length + 1}',
      classId: classId,
      fullNameAr: fullNameAr,
      parentPhone: parentPhone,
    );
    students.add(s);
    return Right(s);
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
  }) async => const Right(null);

  @override
  Future<Either<Failure, void>> deleteStudent(String studentId) async {
    students.removeWhere((s) => s.id == studentId);
    return const Right(null);
  }

  @override
  Future<Either<Failure, List<SundaySchoolAttendanceModel>>>
  fetchAttendanceHistory({required String classId, DateTime? date}) async =>
      const Right([]);

  @override
  Future<Either<Failure, SundaySchoolAnalyticsModel>> fetchAnalytics() async {
    return const Right(
      SundaySchoolAnalyticsModel(
        totalClasses: 1,
        totalServants: 1,
        totalStudents: 1,
        averageAttendanceRate: 85.0,
        stageBreakdown: {'PRIMARY': 1},
      ),
    );
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> recordBulkAttendance({
    required String classId,
    required DateTime sessionDate,
    required List<Map<String, dynamic>> records,
    String? sessionTitle,
  }) async {
    return Right({
      'success': true,
      'recorded_count': records.length,
      'session_date': sessionDate.toIso8601String().split('T').first,
    });
  }
}

void main() {
  group('Sunday School Models', () {
    test('SundaySchoolClassModel serialization', () {
      final json = {
        'id': 'c-100',
        'name_ar': 'فصل يوسف الصديق',
        'stage': 'PREPARATORY',
        'grade_level': 2,
        'academic_year': '2025-2026',
        'tenant_id': 1,
        'created_at': '2026-08-27T10:00:00Z',
      };
      final model = SundaySchoolClassModel.fromJson(json);
      expect(model.id, equals('c-100'));
      expect(model.nameAr, equals('فصل يوسف الصديق'));
      expect(model.stage, equals('PREPARATORY'));
      expect(model.gradeLevel, equals(2));
      expect(model.toJson()['name_ar'], equals('فصل يوسف الصديق'));
    });

    test('SundaySchoolStudentModel serialization', () {
      final json = {
        'id': 'st-100',
        'class_id': 'c-100',
        'full_name_ar': 'مارك يوسف',
        'parent_phone': '+201011112222',
        'is_active': true,
      };
      final model = SundaySchoolStudentModel.fromJson(json);
      expect(model.id, equals('st-100'));
      expect(model.fullNameAr, equals('مارك يوسف'));
      expect(model.parentPhone, equals('+201011112222'));
    });
  });

  group('SupabaseSundaySchoolAdminRepository', () {
    test('recordBulkAttendance invokes RPC correctly', () async {
      Map<String, dynamic>? calledArgs;
      final mock = MockSupabase(
        rpc: {
          'record_bulk_attendance': (args) async {
            calledArgs = args;
            return {
              'success': true,
              'recorded_count': (args['p_records'] as List).length,
              'session_date': args['p_session_date'],
            };
          },
        },
      );

      final repo = SupabaseSundaySchoolAdminRepository(client: mock.build());
      final res = await repo.recordBulkAttendance(
        classId: 'c-99',
        sessionDate: DateTime(2026, 8, 23),
        records: [
          {'student_id': 'st-1', 'status': 'PRESENT'},
          {'student_id': 'st-2', 'status': 'ABSENT'},
        ],
        sessionTitle: 'درس الصدق والأمانة',
      );

      expect(res.isRight, isTrue);
      expect(calledArgs, isNotNull);
      expect(calledArgs!['p_class_id'], equals('c-99'));
      expect(calledArgs!['p_session_date'], equals('2026-08-23'));
      expect(calledArgs!['p_session_title'], equals('درس الصدق والأمانة'));
    });
  });

  group('SundaySchoolAdminDashboard Widget', () {
    testWidgets('renders tabs and dashboard components', (tester) async {
      final repo = FakeSundaySchoolAdminRepository();

      await tester.pumpWidget(
        MaterialApp(home: SundaySchoolAdminDashboard(repository: repo)),
      );

      await tester.pumpAndSettle();

      expect(find.text('إدارة مدارس الأحد والتربية الكنسية'), findsOneWidget);
      expect(find.text('التحليلات والإحصائيات'), findsOneWidget);
      expect(find.text('إدارة الفصول والمراحل'), findsOneWidget);
      expect(find.text('توزيع الخدام'), findsOneWidget);
      expect(find.text('سجلات المخدومين والافتقاد'), findsOneWidget);

      // Verify KPI widgets on analytics tab
      expect(find.text('إجمالي الفصول'), findsOneWidget);
      expect(find.text('إجمالي الخدام'), findsOneWidget);
      expect(find.text('إجمالي المخدومين'), findsOneWidget);
      expect(find.textContaining('نسبة الحضور'), findsOneWidget);
      expect(find.text('85.0%'), findsOneWidget);

      // Switch to Classes tab
      await tester.tap(find.text('إدارة الفصول والمراحل'));
      await tester.pumpAndSettle();
      expect(find.text('فصل داود - رابعة ابتدائي'), findsOneWidget);
      expect(find.text('إضافة فصل جديد'), findsOneWidget);

      // Switch to Servants tab
      await tester.tap(find.text('توزيع الخدام'));
      await tester.pumpAndSettle();
      expect(find.text('الخادم مينا'), findsOneWidget);

      // Switch to Students tab
      await tester.tap(find.text('سجلات المخدومين والافتقاد'));
      await tester.pumpAndSettle();
      expect(find.text('كيرلس مينا'), findsOneWidget);
    });
  });
}
