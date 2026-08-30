import 'package:flutter/material.dart';
import '../../core/either.dart';
import '../../core/failure.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import 'sunday_school_models.dart';
import 'sunday_school_repository.dart';

class ServantAttendanceSheetScreen extends StatefulWidget {
  const ServantAttendanceSheetScreen({
    super.key,
    required this.repository,
    this.initialClassId,
    this.initialClassName,
  });

  final SundaySchoolRepository repository;
  final String? initialClassId;
  final String? initialClassName;

  @override
  State<ServantAttendanceSheetScreen> createState() =>
      _ServantAttendanceSheetScreenState();
}

class _ServantAttendanceSheetScreenState
    extends State<ServantAttendanceSheetScreen> {
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  bool _loading = false;
  String? _errorMessage;
  String? _successMessage;

  List<SundaySchoolClass> _classes = [];
  SundaySchoolClass? _selectedClass;
  List<StudentAttendanceEntry> _attendanceEntries = [];

  int _offlinePendingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadClassesAndInitialData();
  }

  @override
  void dispose() {
    _topicController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadClassesAndInitialData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final queueRes = await widget.repository.getOfflineQueue();
    queueRes.fold((_) {}, (q) => _offlinePendingCount = q.length);

    final classesRes = await widget.repository.fetchMyClasses();
    if (!mounted) return;

    classesRes.fold(
      (err) {
        setState(() {
          _loading = false;
          _errorMessage = err.message;
        });
      },
      (classes) {
        setState(() {
          _classes = classes;
          if (classes.isNotEmpty) {
            if (widget.initialClassId != null) {
              _selectedClass = classes.firstWhere(
                (c) => c.id == widget.initialClassId,
                orElse: () => classes.first,
              );
            } else {
              _selectedClass = classes.first;
            }
          }
        });

        if (_selectedClass != null) {
          _loadRosterForClass(_selectedClass!.id);
        } else {
          setState(() => _loading = false);
        }
      },
    );
  }

  Future<void> _loadRosterForClass(String classId) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final studentsRes = await widget.repository.fetchClassStudents(classId);
    if (!mounted) return;

    studentsRes.fold(
      (err) {
        setState(() {
          _loading = false;
          _errorMessage = err.message;
        });
      },
      (students) {
        setState(() {
          _loading = false;
          _attendanceEntries = students
              .map(
                (s) => StudentAttendanceEntry(
                  studentId: s.id,
                  studentNameAr: s.fullNameAr,
                  status: 'PRESENT',
                ),
              )
              .toList();
        });
      },
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _saveAttendance() async {
    if (_selectedClass == null) return;
    if (_attendanceEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد طلاب في كشف الحضور')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final res = await widget.repository.recordBulkAttendance(
      classId: _selectedClass!.id,
      sessionDate: _selectedDate,
      entries: _attendanceEntries,
      sessionTitle: _topicController.text.trim().isEmpty
          ? null
          : _topicController.text.trim(),
    );

    if (!mounted) return;

    setState(() => _loading = false);

    res.fold(
      (err) {
        setState(() {
          _offlinePendingCount++;
          _errorMessage =
              'تعذر الاتصال بالخادم، تم حفظ الكشف محلياً للمزامنة لاحقاً.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage!),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      },
      (result) {
        final count = result['recorded_count'] ?? _attendanceEntries.length;
        setState(() {
          _successMessage = 'تم تسجيل حضور $count مخدوم بنجاح!';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_successMessage!),
            backgroundColor: Colors.green.shade700,
          ),
        );
      },
    );
  }

  Future<void> _syncOffline() async {
    setState(() => _loading = true);
    final res = await widget.repository.syncOfflineQueue();
    if (!mounted) return;
    setState(() => _loading = false);

    res.fold(
      (err) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشلت المزامنة: ${err.message}')),
        );
      },
      (synced) {
        final queueRes = widget.repository.getOfflineQueue();
        queueRes.then((qr) {
          qr.fold(
            (_) {},
            (q) => setState(() => _offlinePendingCount = q.length),
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت مزامنة $synced كشف بنجاح!'),
            backgroundColor: Colors.green,
          ),
        );
      },
    );
  }

  void _markAll(String status) {
    setState(() {
      for (final entry in _attendanceEntries) {
        entry.status = status;
      }
    });
  }

  Future<void> _showVisitationSheet() async {
    if (_selectedClass == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scrollController) {
          return FutureBuilder<Either<Failure, List<VisitationStudentItem>>>(
            future: widget.repository.fetchVisitationList(
              _selectedClass!.id,
              sessionDate: _selectedDate,
            ),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data;
              List<VisitationStudentItem> list = [];
              if (data != null) {
                list = data.fold(
                  (_) {
                    // Fallback from current local entries
                    final absents = _attendanceEntries
                        .where((e) => e.status == 'ABSENT' || e.status == 'EXCUSED')
                        .toList();
                    return absents
                        .map(
                          (a) => VisitationStudentItem(
                            studentId: a.studentId,
                            studentNameAr: a.studentNameAr,
                            phone: '',
                            parentPhone: '',
                            notes: a.notes ?? '',
                            sessionDate: _selectedDate,
                            attendanceStatus: a.status,
                            consecutiveAbsences: 1,
                          ),
                        )
                        .toList();
                  },
                  (r) => r,
                );
              }


              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '📋 كشف الافتقاد والمتابعة (${list.length})',
                            style: AppTypography.headlineMd.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),

                    const Divider(),
                    if (list.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text(
                            'ممتاز! لا يوجد غائبين بحاجة لافتقاد في هذه الحصة 🎉',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: list.length,
                          itemBuilder: (ctx, i) {
                            final item = list[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: Colors.red.shade200,
                                  width: 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          item.studentNameAr,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade50,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                              color: Colors.red.shade300,
                                            ),
                                          ),
                                          child: Text(
                                            'غياب متكرر: ${item.consecutiveAbsences}',
                                            style: TextStyle(
                                              color: Colors.red.shade800,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    if (item.lastAttendedDate != null)
                                      Text(
                                        'آخر حضور: ${item.lastAttendedDate.toString().split(' ').first}',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    if (item.parentPhone.isNotEmpty)
                                      Text(
                                        'هاتف ولي الأمر: ${item.parentPhone}',
                                        style: TextStyle(
                                          color: Colors.grey.shade800,
                                          fontSize: 13,
                                        ),
                                      ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.end,
                                      children: [
                                        OutlinedButton.icon(
                                          icon: const Icon(
                                            Icons.phone,
                                            size: 16,
                                            color: Colors.blue,
                                          ),
                                          label: const Text('اتصال'),
                                          onPressed: () {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'جاري الاتصال بـ ${item.parentPhone.isNotEmpty ? item.parentPhone : item.studentNameAr}',
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF25D366),
                                            foregroundColor: Colors.white,
                                          ),
                                          icon: const Icon(
                                            Icons.chat,
                                            size: 16,
                                          ),
                                          label: const Text('واتساب'),
                                          onPressed: () {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'فتح محادثة واتساب مع ولي أمر ${item.studentNameAr}',
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();
    final displayedEntries = _attendanceEntries.where((e) {
      return query.isEmpty || e.studentNameAr.contains(query);
    }).toList();

    final presentCount = _attendanceEntries
        .where((e) => e.status == 'PRESENT')
        .length;
    final absentCount = _attendanceEntries
        .where((e) => e.status == 'ABSENT')
        .length;
    final excusedCount = _attendanceEntries
        .where((e) => e.status == 'EXCUSED')
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('كشف حضور مدارس الأحد'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.assignment_ind, size: 18),
            label: const Text('📋 كشف الافتقاد'),
            onPressed: _showVisitationSheet,
          ),
          if (_offlinePendingCount > 0)
            IconButton(
              tooltip:
                  'مزامنة الكشوف المحفوظة دون اتصال ($_offlinePendingCount)',
              icon: Badge(
                label: Text('$_offlinePendingCount'),
                child: const Icon(Icons.cloud_upload),
              ),
              onPressed: _syncOffline,
            ),
        ],
      ),

      body: _loading && _classes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Top control bar
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.cardShadow,
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<SundaySchoolClass>(
                              initialValue: _selectedClass,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'الفصل الدراسي',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(),
                              ),
                              items: _classes
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(
                                        c.nameAr,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null &&
                                    val.id != _selectedClass?.id) {
                                  setState(() => _selectedClass = val);
                                  _loadRosterForClass(val.id);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: Text(
                              '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                              style: AppTypography.bodyMd,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _topicController,
                        decoration: const InputDecoration(
                          hintText: 'عنوان الدرس / موضوع اليوم (اختياري)...',
                          prefixIcon: Icon(Icons.menu_book, size: 20),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),

                // Stats and Quick Actions
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          _buildCountBadge('حاضر', presentCount, Colors.green),
                          const SizedBox(width: 6),
                          _buildCountBadge('غائب', absentCount, Colors.red),
                          const SizedBox(width: 6),
                          _buildCountBadge(
                            'معتذر',
                            excusedCount,
                            Colors.orange,
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => _markAll('PRESENT'),
                            child: const Text('الكل حاضر'),
                          ),
                          TextButton(
                            onPressed: () => _markAll('ABSENT'),
                            child: const Text('الكل غائب'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Search field
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'بحث باسم المخدوم...',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),

                // Student List
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : displayedEntries.isEmpty
                      ? const Center(
                          child: Text('لا يوجد مخدومين مسجلين في هذا الفصل'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: displayedEntries.length,
                          itemBuilder: (ctx, idx) {
                            final entry = displayedEntries[idx];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        entry.studentNameAr,
                                        style: AppTypography.bodyLg.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    _buildStatusButton(
                                      label: 'حاضر',
                                      status: 'PRESENT',
                                      currentStatus: entry.status,
                                      color: Colors.green,
                                      onTap: () {
                                        setState(
                                          () => entry.status = 'PRESENT',
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    _buildStatusButton(
                                      label: 'غائب',
                                      status: 'ABSENT',
                                      currentStatus: entry.status,
                                      color: Colors.red,
                                      onTap: () {
                                        setState(() => entry.status = 'ABSENT');
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    _buildStatusButton(
                                      label: 'معتذر',
                                      status: 'EXCUSED',
                                      currentStatus: entry.status,
                                      color: Colors.orange,
                                      onTap: () {
                                        setState(
                                          () => entry.status = 'EXCUSED',
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Bottom Save Action
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.cardShadow,
                        blurRadius: 10,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _saveAttendance,
                      icon: const Icon(Icons.check),
                      label: Text(
                        _loading ? 'جاري الحفظ...' : 'حفظ كشف الحضور',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCountBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(fontSize: 12, color: color)),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusButton({
    required String label,
    required String status,
    required String currentStatus,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isSelected = currentStatus == status;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
