import 'package:flutter/material.dart';
import 'sunday_school_admin_repository.dart';
import 'sunday_school_models.dart';

class SundaySchoolAdminDashboard extends StatefulWidget {
  const SundaySchoolAdminDashboard({super.key, required this.repository});

  final SundaySchoolAdminRepository repository;

  @override
  State<SundaySchoolAdminDashboard> createState() =>
      _SundaySchoolAdminDashboardState();
}

class _SundaySchoolAdminDashboardState extends State<SundaySchoolAdminDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _loading = false;
  String? _errorMessage;

  List<SundaySchoolClassModel> _classes = [];
  List<SundaySchoolServantModel> _servants = [];
  List<SundaySchoolStudentModel> _students = [];
  SundaySchoolAnalyticsModel? _analytics;

  String? _selectedClassFilter;
  String _studentSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final classesRes = await widget.repository.fetchClasses();
    final servantsRes = await widget.repository.fetchServants();
    final studentsRes = await widget.repository.fetchStudents();
    final analyticsRes = await widget.repository.fetchAnalytics();

    if (!mounted) return;

    setState(() {
      _loading = false;
      classesRes.fold((l) => _errorMessage = l.message, (r) => _classes = r);
      servantsRes.fold(
        (l) => _errorMessage = _errorMessage ?? l.message,
        (r) => _servants = r,
      );
      studentsRes.fold(
        (l) => _errorMessage = _errorMessage ?? l.message,
        (r) => _students = r,
      );
      analyticsRes.fold((_) {}, (r) => _analytics = r);
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

  String _roleLabel(String role) {
    switch (role) {
      case 'LEADER':
        return 'أمين أسرة / قائد';
      case 'ASSISTANT':
        return 'مساعد خادم';
      case 'SERVANT':
      default:
        return 'خادم';
    }
  }

  // ---------------------------------------------------- Dialogs
  Future<void> _showAddClassDialog([SundaySchoolClassModel? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.nameAr ?? '');
    final gradeCtrl = TextEditingController(
      text: existing?.gradeLevel?.toString() ?? '',
    );
    final yearCtrl = TextEditingController(
      text: existing?.academicYear ?? '2025-2026',
    );
    String stage = existing?.stage ?? 'PRIMARY';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(
            existing == null ? 'إضافة فصل جديد' : 'تعديل بيانات الفصل',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم الفصل (عربي)',
                    hintText: 'مثال: أسرة مارمرقس - رابعة ابتدائي',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: stage,
                  decoration: const InputDecoration(
                    labelText: 'المرحلة الدراسية',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'NURSERY', child: Text('حضانة')),
                    DropdownMenuItem(value: 'PRIMARY', child: Text('ابتدائي')),
                    DropdownMenuItem(
                      value: 'PREPARATORY',
                      child: Text('إعدادي'),
                    ),
                    DropdownMenuItem(value: 'SECONDARY', child: Text('ثانوي')),
                    DropdownMenuItem(
                      value: 'UNIVERSITY',
                      child: Text('جامعيين'),
                    ),
                    DropdownMenuItem(value: 'GENERAL', child: Text('عام')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDlgState(() => stage = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: gradeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الصف الدراسي (اختياري)',
                    hintText: '1, 2, 3...',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: yearCtrl,
                  decoration: const InputDecoration(
                    labelText: 'السنة الدراسية',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final grade = int.tryParse(gradeCtrl.text.trim());
                if (existing == null) {
                  await widget.repository.createClass(
                    nameAr: nameCtrl.text.trim(),
                    stage: stage,
                    gradeLevel: grade,
                    academicYear: yearCtrl.text.trim(),
                  );
                } else {
                  await widget.repository.updateClass(
                    classId: existing.id,
                    nameAr: nameCtrl.text.trim(),
                    stage: stage,
                    gradeLevel: grade,
                    academicYear: yearCtrl.text.trim(),
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _loadAllData();
    }
  }

  Future<void> _showAssignServantDialog() async {
    if (_classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إنشاء فصل أولاً قبل تعيين الخدام')),
      );
      return;
    }

    String selectedClassId = _classes.first.id;
    final userIdCtrl = TextEditingController();
    String role = 'SERVANT';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('تعيين خادم لفصل'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedClassId,
                  decoration: const InputDecoration(labelText: 'الفصل'),
                  items: _classes
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.nameAr),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setDlgState(() => selectedClassId = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'معرف الخادم (User UUID)',
                    hintText: 'ffffffff-...',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'الدور'),
                  items: const [
                    DropdownMenuItem(
                      value: 'LEADER',
                      child: Text('أمين أسرة / قائد'),
                    ),
                    DropdownMenuItem(value: 'SERVANT', child: Text('خادم')),
                    DropdownMenuItem(
                      value: 'ASSISTANT',
                      child: Text('مساعد خادم'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setDlgState(() => role = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (userIdCtrl.text.trim().isEmpty) return;
                await widget.repository.assignServant(
                  classId: selectedClassId,
                  userId: userIdCtrl.text.trim(),
                  role: role,
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('تعيين'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _loadAllData();
    }
  }

  Future<void> _showAddStudentDialog([
    SundaySchoolStudentModel? existing,
  ]) async {
    if (_classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إنشاء فصل أولاً قبل إضافة الطلاب')),
      );
      return;
    }

    String selectedClassId = existing?.classId ?? _classes.first.id;
    final nameCtrl = TextEditingController(text: existing?.fullNameAr ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final parentPhoneCtrl = TextEditingController(
      text: existing?.parentPhone ?? '',
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    DateTime? birthDate = existing?.birthDate;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(
            existing == null ? 'إضافة مخدوم جديد' : 'تعديل بيانات المخدوم',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedClassId,
                  decoration: const InputDecoration(labelText: 'الفصل'),
                  items: _classes
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.nameAr),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setDlgState(() => selectedClassId = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الثلاثي / الرباعي',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: parentPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'هاتف ولي الأمر',
                    hintText: '+2010xxxxxxxx',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'هاتف المخدوم (إن وجد)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات الافتقاد والرعاية',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                if (existing == null) {
                  await widget.repository.addStudent(
                    classId: selectedClassId,
                    fullNameAr: nameCtrl.text.trim(),
                    parentPhone: parentPhoneCtrl.text.trim().isEmpty
                        ? null
                        : parentPhoneCtrl.text.trim(),
                    phone: phoneCtrl.text.trim().isEmpty
                        ? null
                        : phoneCtrl.text.trim(),
                    birthDate: birthDate,
                    notes: notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
                  );
                } else {
                  await widget.repository.updateStudent(
                    studentId: existing.id,
                    classId: selectedClassId,
                    fullNameAr: nameCtrl.text.trim(),
                    parentPhone: parentPhoneCtrl.text.trim().isEmpty
                        ? null
                        : parentPhoneCtrl.text.trim(),
                    phone: phoneCtrl.text.trim().isEmpty
                        ? null
                        : phoneCtrl.text.trim(),
                    birthDate: birthDate,
                    notes: notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _loadAllData();
    }
  }

  // ---------------------------------------------------- Tabs
  Widget _buildAnalyticsTab() {
    final analytics = _analytics ?? const SundaySchoolAnalyticsModel();
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'نظرة عامة على خدمة مدارس الأحد',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 600;
                if (isNarrow) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          _buildKpiCard(
                            'إجمالي الفصول',
                            '${analytics.totalClasses}',
                            Icons.class_outlined,
                            Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          _buildKpiCard(
                            'إجمالي الخدام',
                            '${analytics.totalServants}',
                            Icons.people_outline,
                            Colors.teal,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildKpiCard(
                            'إجمالي المخدومين',
                            '${analytics.totalStudents}',
                            Icons.school_outlined,
                            Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          _buildKpiCard(
                            'نسبة الحضور',
                            '${analytics.averageAttendanceRate.toStringAsFixed(1)}%',
                            Icons.check_circle_outline,
                            Colors.green,
                          ),
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    _buildKpiCard(
                      'إجمالي الفصول',
                      '${analytics.totalClasses}',
                      Icons.class_outlined,
                      Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    _buildKpiCard(
                      'إجمالي الخدام',
                      '${analytics.totalServants}',
                      Icons.people_outline,
                      Colors.teal,
                    ),
                    const SizedBox(width: 12),
                    _buildKpiCard(
                      'إجمالي المخدومين',
                      '${analytics.totalStudents}',
                      Icons.school_outlined,
                      Colors.orange,
                    ),
                    const SizedBox(width: 12),
                    _buildKpiCard(
                      'نسبة الحضور',
                      '${analytics.averageAttendanceRate.toStringAsFixed(1)}%',
                      Icons.check_circle_outline,
                      Colors.green,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'توزيع الفصول حسب المراحل الدراسية',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (analytics.stageBreakdown.isEmpty)
                      const Text('لا توجد بيانات حالياً')
                    else
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: analytics.stageBreakdown.entries.map((e) {
                          return Chip(
                            avatar: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: Text(
                                '${e.value}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            label: Text('${_stageLabel(e.key)} (${e.value})'),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClassesTab() {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddClassDialog(),
        icon: const Icon(Icons.add),
        label: const Text('إضافة فصل جديد'),
      ),
      body: _classes.isEmpty
          ? const Center(child: Text('لا توجد فصول دراسية مسجلة حالياً'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _classes.length,
              itemBuilder: (ctx, idx) {
                final item = _classes[idx];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade50,
                      child: Text('${item.gradeLevel ?? "-"}'),
                    ),
                    title: Text(
                      item.nameAr,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'المرحلة: ${_stageLabel(item.stage)} | العام: ${item.academicYear}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(
                          label: Text('${item.servantsCount} خادم'),
                          backgroundColor: Colors.teal.shade50,
                        ),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text('${item.studentsCount} مخدوم'),
                          backgroundColor: Colors.orange.shade50,
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showAddClassDialog(item),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('تأكيد الحذف'),
                                content: Text(
                                  'هل أنت متأكد من حذف فصل "${item.nameAr}"؟',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('إلغاء'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('حذف'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await widget.repository.deleteClass(item.id);
                              _loadAllData();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildServantsTab() {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAssignServantDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('تعيين خادم لفصل'),
      ),
      body: _servants.isEmpty
          ? const Center(child: Text('لا توجد تعيينات خدام مسجلة حالياً'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _servants.length,
              itemBuilder: (ctx, idx) {
                final item = _servants[idx];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(
                      item.userName ?? item.userId,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'الفصل: ${item.classNameAr ?? item.classId} | الهاتف: ${item.userPhone ?? "غير مسجل"}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(
                          label: Text(_roleLabel(item.role)),
                          backgroundColor: item.role == 'LEADER'
                              ? Colors.amber.shade100
                              : Colors.blue.shade50,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            await widget.repository.removeServant(item.id);
                            _loadAllData();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStudentsTab() {
    final filtered = _students.where((s) {
      final matchesClass =
          _selectedClassFilter == null || s.classId == _selectedClassFilter;
      final matchesSearch =
          _studentSearchQuery.isEmpty ||
          s.fullNameAr.contains(_studentSearchQuery) ||
          (s.parentPhone?.contains(_studentSearchQuery) ?? false) ||
          (s.phone?.contains(_studentSearchQuery) ?? false);
      return matchesClass && matchesSearch;
    }).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddStudentDialog(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('إضافة مخدوم جديد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'بحث باسم المخدوم أو رقم الهاتف...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) =>
                        setState(() => _studentSearchQuery = val),
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String?>(
                  value: _selectedClassFilter,
                  hint: const Text('كل الفصول'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('كل الفصول'),
                    ),
                    ..._classes.map(
                      (c) =>
                          DropdownMenuItem(value: c.id, child: Text(c.nameAr)),
                    ),
                  ],
                  onChanged: (val) =>
                      setState(() => _selectedClassFilter = val),
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('لا يوجد مخدومين مطابقين للبحث'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, idx) {
                      final item = filtered[idx];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            item.fullNameAr,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'الفصل: ${item.classNameAr ?? "غير محدد"} | هاتف ولي الأمر: ${item.parentPhone ?? "غير متوفر"}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item.notes != null && item.notes!.isNotEmpty)
                                Tooltip(
                                  message: item.notes!,
                                  child: const Icon(
                                    Icons.notes,
                                    color: Colors.grey,
                                  ),
                                ),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
                                onPressed: () => _showAddStudentDialog(item),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () async {
                                  await widget.repository.deleteStudent(
                                    item.id,
                                  );
                                  _loadAllData();
                                },
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة مدارس الأحد والتربية الكنسية'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart), text: 'التحليلات والإحصائيات'),
            Tab(icon: Icon(Icons.school), text: 'إدارة الفصول والمراحل'),
            Tab(icon: Icon(Icons.people), text: 'توزيع الخدام'),
            Tab(icon: Icon(Icons.menu_book), text: 'سجلات المخدومين والافتقاد'),
          ],
        ),
      ),
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
                    onPressed: _loadAllData,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAnalyticsTab(),
                _buildClassesTab(),
                _buildServantsTab(),
                _buildStudentsTab(),
              ],
            ),
    );
  }
}
