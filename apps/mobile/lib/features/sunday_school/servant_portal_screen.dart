import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import 'servant_attendance_sheet_screen.dart';
import 'sunday_school_models.dart';
import 'sunday_school_repository.dart';

class ServantPortalScreen extends StatefulWidget {
  const ServantPortalScreen({super.key, required this.repository});

  final SundaySchoolRepository repository;

  @override
  State<ServantPortalScreen> createState() => _ServantPortalScreenState();
}

class _ServantPortalScreenState extends State<ServantPortalScreen> {
  bool _loading = false;
  String? _errorMessage;
  List<SundaySchoolClass> _classes = [];

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final res = await widget.repository.fetchMyClasses();
    if (!mounted) return;

    setState(() {
      _loading = false;
      res.fold(
        (err) => _errorMessage = err.message,
        (classes) => _classes = classes,
      );
    });
  }

  String _stageLabel(String stage) {
    switch (stage) {
      case 'NURSERY':
        return 'حضانة';
      case 'PRIMARY':
        return 'ابتدائي';
      case 'PREPARATORY':
        return 'إعدادي';
      case 'SECONDARY':
        return 'ثانوي';
      case 'UNIVERSITY':
        return 'جامعيين';
      case 'GENERAL':
      default:
        return 'عام';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بوابة الخدام والتربية الكنسية')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'خطأ: $_errorMessage',
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadClasses,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            )
          : _classes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.school_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'لا توجد فصول دراسية مسندة إليك حالياً',
                    style: AppTypography.bodyLg,
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadClasses,
              child: ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.marginMobile),
                itemCount: _classes.length,
                itemBuilder: (ctx, idx) {
                  final item = _classes[idx];
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  item.nameAr,
                                  style: AppTypography.headlineMd.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Chip(
                                label: Text(_stageLabel(item.stage)),
                                backgroundColor: AppColors.secondaryContainer,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'العام الدراسي: ${item.academicYear}${item.gradeLevel != null ? ' | الصف: ${item.gradeLevel}' : ''}',
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ServantAttendanceSheetScreen(
                                          repository: widget.repository,
                                          initialClassId: item.id,
                                          initialClassName: item.nameAr,
                                        ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.checklist),
                              label: const Text('تسجيل الحضور الأسبوعي'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
