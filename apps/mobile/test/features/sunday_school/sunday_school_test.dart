import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/either.dart';
import 'package:mobile/core/failure.dart';
import 'package:mobile/features/sunday_school/servant_attendance_sheet_screen.dart';
import 'package:mobile/features/sunday_school/servant_portal_screen.dart';
import 'package:mobile/features/sunday_school/sunday_school_models.dart';
import 'package:mobile/features/sunday_school/sunday_school_repository.dart';

class FakeSundaySchoolRepository implements SundaySchoolRepository {
  final List<SundaySchoolClass> classes = [
    const SundaySchoolClass(
      id: 'c-1',
      nameAr: 'فصل داود النبي - رابعة ابتدائي',
      stage: 'PRIMARY',
      gradeLevel: 4,
      academicYear: '2025-2026',
    ),
  ];

  final List<SundaySchoolStudent> students = [
    const SundaySchoolStudent(
      id: 'st-1',
      classId: 'c-1',
      fullNameAr: 'كيرلس مينا',
      parentPhone: '+201011112222',
    ),
    const SundaySchoolStudent(
      id: 'st-2',
      classId: 'c-1',
      fullNameAr: 'يوسف سامح',
      parentPhone: '+201033334444',
    ),
  ];

  final List<OfflineAttendanceMutation> offlineQueue = [];
  bool recordBulkAttendanceShouldFail = false;

  @override
  Future<Either<Failure, List<SundaySchoolClass>>> fetchMyClasses() async =>
      Right(classes);

  @override
  Future<Either<Failure, List<SundaySchoolStudent>>> fetchClassStudents(
    String classId,
  ) async => Right(students);

  @override
  Future<Either<Failure, Map<String, dynamic>>> recordBulkAttendance({
    required String classId,
    required DateTime sessionDate,
    required List<StudentAttendanceEntry> entries,
    String? sessionTitle,
  }) async {
    if (recordBulkAttendanceShouldFail) {
      final mutation = OfflineAttendanceMutation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        classId: classId,
        sessionDate: sessionDate,
        sessionTitle: sessionTitle,
        records: entries.map((e) => e.toJson()).toList(),
        createdAt: DateTime.now(),
      );
      offlineQueue.add(mutation);
      return const Left(NetworkFailure('لا يوجد اتصال بالإنترنت'));
    }

    return Right({
      'success': true,
      'recorded_count': entries.length,
      'session_date': sessionDate.toIso8601String().split('T').first,
    });
  }

  @override
  Future<Either<Failure, List<OfflineAttendanceMutation>>>
  getOfflineQueue() async => Right(offlineQueue);

  @override
  Future<Either<Failure, void>> enqueueOfflineAttendance(
    OfflineAttendanceMutation mutation,
  ) async {
    offlineQueue.add(mutation);
    return const Right(null);
  }

  @override
  Future<Either<Failure, int>> syncOfflineQueue() async {
    final count = offlineQueue.length;
    offlineQueue.clear();
    return Right(count);
  }
}

void main() {
  group('Sunday School Mobile Models', () {
    test('SundaySchoolClass and Student parsing', () {
      final classModel = SundaySchoolClass.fromJson({
        'id': 'c-1',
        'name_ar': 'فصل مارمرقس',
        'stage': 'PREPARATORY',
        'grade_level': 1,
        'academic_year': '2025-2026',
      });
      expect(classModel.id, equals('c-1'));
      expect(classModel.nameAr, equals('فصل مارمرقس'));
      expect(classModel.stage, equals('PREPARATORY'));

      final student = SundaySchoolStudent.fromJson({
        'id': 'st-1',
        'class_id': 'c-1',
        'full_name_ar': 'مارك يوسف',
        'parent_phone': '+201012345678',
      });
      expect(student.id, equals('st-1'));
      expect(student.fullNameAr, equals('مارك يوسف'));
    });

    test(
      'StudentAttendanceEntry and OfflineAttendanceMutation serialization',
      () {
        final entry = StudentAttendanceEntry(
          studentId: 'st-1',
          studentNameAr: 'مارك يوسف',
          status: 'PRESENT',
          notes: 'حاضر مبكراً',
        );
        final json = entry.toJson();
        expect(json['student_id'], equals('st-1'));
        expect(json['status'], equals('PRESENT'));
        expect(json['notes'], equals('حاضر مبكراً'));

        final mutation = OfflineAttendanceMutation(
          id: 'm-1',
          classId: 'c-1',
          sessionDate: DateTime(2026, 8, 23),
          sessionTitle: 'درس الصدق',
          records: [json],
          createdAt: DateTime.now(),
        );
        final mutationJson = mutation.toJson();
        expect(mutationJson['class_id'], equals('c-1'));
        expect(mutationJson['session_date'], equals('2026-08-23'));
      },
    );
  });

  group('ServantPortalScreen Widget', () {
    testWidgets('renders assigned classes and navigates', (tester) async {
      final repo = FakeSundaySchoolRepository();

      await tester.pumpWidget(
        MaterialApp(home: ServantPortalScreen(repository: repo)),
      );

      await tester.pumpAndSettle();

      expect(find.text('بوابة الخدام والتربية الكنسية'), findsOneWidget);
      expect(find.text('فصل داود النبي - رابعة ابتدائي'), findsOneWidget);
      expect(find.text('ابتدائي'), findsOneWidget);
      expect(find.text('تسجيل الحضور الأسبوعي'), findsOneWidget);
    });
  });

  group('ServantAttendanceSheetScreen Widget', () {
    testWidgets('renders student checklist and saves attendance', (
      tester,
    ) async {
      final repo = FakeSundaySchoolRepository();

      await tester.pumpWidget(
        MaterialApp(home: ServantAttendanceSheetScreen(repository: repo)),
      );

      await tester.pumpAndSettle();

      expect(find.text('كشف حضور مدارس الأحد'), findsOneWidget);
      expect(find.text('كيرلس مينا'), findsOneWidget);
      expect(find.text('يوسف سامح'), findsOneWidget);

      // Verify status buttons
      expect(find.text('حاضر'), findsWidgets);
      expect(find.text('غائب'), findsWidgets);
      expect(find.text('معتذر'), findsWidgets);

      // Tap Save button
      await tester.tap(find.text('حفظ كشف الحضور'));
      await tester.pumpAndSettle();

      expect(find.text('تم تسجيل حضور 2 مخدوم بنجاح!'), findsOneWidget);
    });

    testWidgets('queues offline mutation when network fails', (tester) async {
      final repo = FakeSundaySchoolRepository();
      repo.recordBulkAttendanceShouldFail = true;

      await tester.pumpWidget(
        MaterialApp(home: ServantAttendanceSheetScreen(repository: repo)),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('حفظ كشف الحضور'));
      await tester.pumpAndSettle();

      expect(repo.offlineQueue.length, equals(1));
      expect(find.textContaining('تم حفظ الكشف محلياً'), findsOneWidget);
    });
  });
}
