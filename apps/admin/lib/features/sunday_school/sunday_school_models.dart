class SundaySchoolClassModel {
  final String id;
  final String nameAr;
  final String stage;
  final int? gradeLevel;
  final String academicYear;
  final int tenantId;
  final DateTime? createdAt;
  final int servantsCount;
  final int studentsCount;

  const SundaySchoolClassModel({
    required this.id,
    required this.nameAr,
    required this.stage,
    this.gradeLevel,
    this.academicYear = '2025-2026',
    this.tenantId = 1,
    this.createdAt,
    this.servantsCount = 0,
    this.studentsCount = 0,
  });

  factory SundaySchoolClassModel.fromJson(Map<String, dynamic> json) {
    return SundaySchoolClassModel(
      id: json['id'] as String? ?? '',
      nameAr: json['name_ar'] as String? ?? '',
      stage: json['stage'] as String? ?? 'PRIMARY',
      gradeLevel: json['grade_level'] as int?,
      academicYear: json['academic_year'] as String? ?? '2025-2026',
      tenantId: json['tenant_id'] as int? ?? 1,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      servantsCount: json['servants_count'] as int? ?? 0,
      studentsCount: json['students_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name_ar': nameAr,
    'stage': stage,
    'grade_level': gradeLevel,
    'academic_year': academicYear,
    'tenant_id': tenantId,
  };
}

class SundaySchoolServantModel {
  final String id;
  final String classId;
  final String userId;
  final String role;
  final bool isActive;
  final String? userName;
  final String? userPhone;
  final String? classNameAr;
  final DateTime? createdAt;

  const SundaySchoolServantModel({
    required this.id,
    required this.classId,
    required this.userId,
    this.role = 'SERVANT',
    this.isActive = true,
    this.userName,
    this.userPhone,
    this.classNameAr,
    this.createdAt,
  });

  factory SundaySchoolServantModel.fromJson(Map<String, dynamic> json) {
    final userObj = json['users'] is Map<String, dynamic>
        ? json['users'] as Map<String, dynamic>
        : null;
    final classObj = json['sunday_school_classes'] is Map<String, dynamic>
        ? json['sunday_school_classes'] as Map<String, dynamic>
        : null;

    return SundaySchoolServantModel(
      id: json['id'] as String? ?? '',
      classId: json['class_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      role: json['role'] as String? ?? 'SERVANT',
      isActive: json['is_active'] as bool? ?? true,
      userName: userObj?['name'] as String?,
      userPhone: userObj?['phone'] as String?,
      classNameAr: classObj?['name_ar'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'class_id': classId,
    'user_id': userId,
    'role': role,
    'is_active': isActive,
  };
}

class SundaySchoolStudentModel {
  final String id;
  final String classId;
  final String fullNameAr;
  final DateTime? birthDate;
  final String? phone;
  final String? parentPhone;
  final String? userId;
  final String? notes;
  final bool isActive;
  final String? classNameAr;
  final DateTime? createdAt;

  const SundaySchoolStudentModel({
    required this.id,
    required this.classId,
    required this.fullNameAr,
    this.birthDate,
    this.phone,
    this.parentPhone,
    this.userId,
    this.notes,
    this.isActive = true,
    this.classNameAr,
    this.createdAt,
  });

  factory SundaySchoolStudentModel.fromJson(Map<String, dynamic> json) {
    final classObj = json['sunday_school_classes'] is Map<String, dynamic>
        ? json['sunday_school_classes'] as Map<String, dynamic>
        : null;

    return SundaySchoolStudentModel(
      id: json['id'] as String? ?? '',
      classId: json['class_id'] as String? ?? '',
      fullNameAr: json['full_name_ar'] as String? ?? '',
      birthDate: json['birth_date'] != null
          ? DateTime.tryParse(json['birth_date'] as String)
          : null,
      phone: json['phone'] as String?,
      parentPhone: json['parent_phone'] as String?,
      userId: json['user_id'] as String?,
      notes: json['notes'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      classNameAr: classObj?['name_ar'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'class_id': classId,
    'full_name_ar': fullNameAr,
    'birth_date': birthDate?.toIso8601String().split('T').first,
    'phone': phone,
    'parent_phone': parentPhone,
    'user_id': userId,
    'notes': notes,
    'is_active': isActive,
  };
}

class SundaySchoolSessionModel {
  final String id;
  final String classId;
  final DateTime sessionDate;
  final String? topicTitleAr;
  final String? servantId;
  final String? servantName;
  final int presentCount;
  final int absentCount;
  final int excusedCount;

  const SundaySchoolSessionModel({
    required this.id,
    required this.classId,
    required this.sessionDate,
    this.topicTitleAr,
    this.servantId,
    this.servantName,
    this.presentCount = 0,
    this.absentCount = 0,
    this.excusedCount = 0,
  });

  factory SundaySchoolSessionModel.fromJson(Map<String, dynamic> json) {
    final userObj = json['users'] is Map<String, dynamic>
        ? json['users'] as Map<String, dynamic>
        : null;

    return SundaySchoolSessionModel(
      id: json['id'] as String? ?? '',
      classId: json['class_id'] as String? ?? '',
      sessionDate: json['session_date'] != null
          ? DateTime.parse(json['session_date'] as String)
          : DateTime.now(),
      topicTitleAr: json['topic_title_ar'] as String?,
      servantId: json['servant_id'] as String?,
      servantName: userObj?['name'] as String?,
      presentCount: json['present_count'] as int? ?? 0,
      absentCount: json['absent_count'] as int? ?? 0,
      excusedCount: json['excused_count'] as int? ?? 0,
    );
  }
}

class SundaySchoolAttendanceModel {
  final String id;
  final String classId;
  final String studentId;
  final String? studentNameAr;
  final DateTime sessionDate;
  final String status;
  final String? recordedBy;
  final String? notes;

  const SundaySchoolAttendanceModel({
    required this.id,
    required this.classId,
    required this.studentId,
    this.studentNameAr,
    required this.sessionDate,
    this.status = 'PRESENT',
    this.recordedBy,
    this.notes,
  });

  factory SundaySchoolAttendanceModel.fromJson(Map<String, dynamic> json) {
    final studentObj = json['sunday_school_students'] is Map<String, dynamic>
        ? json['sunday_school_students'] as Map<String, dynamic>
        : null;

    return SundaySchoolAttendanceModel(
      id: json['id'] as String? ?? '',
      classId: json['class_id'] as String? ?? '',
      studentId: json['student_id'] as String? ?? '',
      studentNameAr: studentObj?['full_name_ar'] as String?,
      sessionDate: json['session_date'] != null
          ? DateTime.parse(json['session_date'] as String)
          : DateTime.now(),
      status: json['status'] as String? ?? 'PRESENT',
      recordedBy: json['recorded_by'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'class_id': classId,
    'student_id': studentId,
    'session_date': sessionDate.toIso8601String().split('T').first,
    'status': status,
    'notes': notes,
  };
}

class SundaySchoolAnalyticsModel {
  final int totalClasses;
  final int totalServants;
  final int totalStudents;
  final double averageAttendanceRate;
  final Map<String, int> stageBreakdown;

  const SundaySchoolAnalyticsModel({
    this.totalClasses = 0,
    this.totalServants = 0,
    this.totalStudents = 0,
    this.averageAttendanceRate = 0.0,
    this.stageBreakdown = const {},
  });
}
