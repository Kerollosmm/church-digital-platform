class SundaySchoolClass {
  final String id;
  final String nameAr;
  final String stage;
  final int? gradeLevel;
  final String academicYear;

  const SundaySchoolClass({
    required this.id,
    required this.nameAr,
    required this.stage,
    this.gradeLevel,
    this.academicYear = '2025-2026',
  });

  factory SundaySchoolClass.fromJson(Map<String, dynamic> json) {
    return SundaySchoolClass(
      id: json['id'] as String? ?? '',
      nameAr: json['name_ar'] as String? ?? '',
      stage: json['stage'] as String? ?? 'PRIMARY',
      gradeLevel: json['grade_level'] as int?,
      academicYear: json['academic_year'] as String? ?? '2025-2026',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name_ar': nameAr,
    'stage': stage,
    'grade_level': gradeLevel,
    'academic_year': academicYear,
  };
}

class SundaySchoolStudent {
  final String id;
  final String classId;
  final String fullNameAr;
  final DateTime? birthDate;
  final String? phone;
  final String? parentPhone;
  final String? notes;
  final bool isActive;

  const SundaySchoolStudent({
    required this.id,
    required this.classId,
    required this.fullNameAr,
    this.birthDate,
    this.phone,
    this.parentPhone,
    this.notes,
    this.isActive = true,
  });

  factory SundaySchoolStudent.fromJson(Map<String, dynamic> json) {
    return SundaySchoolStudent(
      id: json['id'] as String? ?? '',
      classId: json['class_id'] as String? ?? '',
      fullNameAr: json['full_name_ar'] as String? ?? '',
      birthDate: json['birth_date'] != null
          ? DateTime.tryParse(json['birth_date'] as String)
          : null,
      phone: json['phone'] as String?,
      parentPhone: json['parent_phone'] as String?,
      notes: json['notes'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'class_id': classId,
    'full_name_ar': fullNameAr,
    'birth_date': birthDate?.toIso8601String().split('T').first,
    'phone': phone,
    'parent_phone': parentPhone,
    'notes': notes,
    'is_active': isActive,
  };
}

class StudentAttendanceEntry {
  final String studentId;
  final String studentNameAr;
  String status; // 'PRESENT', 'ABSENT', 'EXCUSED'
  String? notes;

  StudentAttendanceEntry({
    required this.studentId,
    required this.studentNameAr,
    this.status = 'PRESENT',
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    'student_id': studentId,
    'status': status,
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
  };

  factory StudentAttendanceEntry.fromJson(Map<String, dynamic> json) {
    return StudentAttendanceEntry(
      studentId: json['student_id'] as String? ?? '',
      studentNameAr: json['student_name_ar'] as String? ?? '',
      status: json['status'] as String? ?? 'PRESENT',
      notes: json['notes'] as String?,
    );
  }
}

class OfflineAttendanceMutation {
  final String id;
  final String classId;
  final DateTime sessionDate;
  final String? sessionTitle;
  final List<Map<String, dynamic>> records;
  final DateTime createdAt;
  bool isSynced;

  OfflineAttendanceMutation({
    required this.id,
    required this.classId,
    required this.sessionDate,
    this.sessionTitle,
    required this.records,
    required this.createdAt,
    this.isSynced = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'class_id': classId,
    'session_date': sessionDate.toIso8601String().split('T').first,
    'session_title': sessionTitle,
    'records': records,
    'created_at': createdAt.toIso8601String(),
    'is_synced': isSynced,
  };

  factory OfflineAttendanceMutation.fromJson(Map<String, dynamic> json) {
    return OfflineAttendanceMutation(
      id: json['id'] as String? ?? '',
      classId: json['class_id'] as String? ?? '',
      sessionDate: json['session_date'] != null
          ? DateTime.parse(json['session_date'] as String)
          : DateTime.now(),
      sessionTitle: json['session_title'] as String?,
      records: (json['records'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      isSynced: json['is_synced'] as bool? ?? false,
    );
  }
}
