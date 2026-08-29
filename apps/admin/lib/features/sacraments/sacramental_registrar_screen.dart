import 'package:flutter/material.dart';
import 'issue_sacrament_dialog.dart';
import 'sacrament_details_dialog.dart';
import 'sacramental_models.dart';
import 'sacraments_admin_repository.dart';

class SacramentalRegistrarScreen extends StatefulWidget {
  const SacramentalRegistrarScreen({super.key, required this.repository});

  final SacramentsAdminRepository repository;

  @override
  State<SacramentalRegistrarScreen> createState() =>
      _SacramentalRegistrarScreenState();
}

class _SacramentalRegistrarScreenState
    extends State<SacramentalRegistrarScreen> {
  List<SacramentalRecord> _records = [];
  bool _isLoading = true;
  String? _errorMessage;

  String _selectedTypeFilter = 'ALL';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await widget.repository.fetchSacramentalRecords(
      sacramentTypeFilter: _selectedTypeFilter == 'ALL'
          ? null
          : _selectedTypeFilter,
      searchQuery: _searchController.text.trim().isEmpty
          ? null
          : _searchController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      res.fold(
        (failure) => _errorMessage = failure.message,
        (records) => _records = records,
      );
    });
  }

  Future<void> _onIssueCertificate() async {
    final record = await IssueSacramentDialog.show(context, widget.repository);
    if (record != null) {
      _loadRecords();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم إصدار الشهادة بنجاح')));
      }
    }
  }

  Future<void> _onRevokeCertificate(SacramentalRecord record) async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.red),
            const SizedBox(width: 8),
            Text('إلغاء ${record.sacramentType.labelAr}'),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('صاحب الشهادة: ${record.recipientNameAr}'),
              const SizedBox(height: 12),
              const Text(
                'تنبيه: إلغاء الشهادة إجراء رسمي يوقف صلاحية رمز التحقق الرقمي.',
                style: TextStyle(color: Colors.red, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'سبب الإلغاء الرسمي *',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'يرجى إدخال سبب الإلغاء';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text(
              'تأكيد الإلغاء',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final res = await widget.repository.revokeCertificate(
        recordId: record.id,
        reason: reasonController.text.trim(),
      );

      if (!mounted) return;

      res.fold(
        (failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل إلغاء الشهادة: ${failure.message}')),
          );
        },
        (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إلغاء الشهادة وتحديث السجل')),
          );
          _loadRecords();
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجلات الأسرار والشهادات الكنسية'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: ElevatedButton.icon(
              onPressed: _onIssueCertificate,
              icon: const Icon(Icons.add),
              label: const Text('إصدار شهادة جديدة'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'بحث باسم صاحب السر...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _loadRecords();
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _loadRecords(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedTypeFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'نوع السر',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'ALL',
                        child: Text('جميع الأسرار'),
                      ),
                      DropdownMenuItem(
                        value: 'BAPTISM',
                        child: Text('سر المعمودية'),
                      ),
                      DropdownMenuItem(
                        value: 'MARRIAGE',
                        child: Text('سر الزيجة'),
                      ),
                      DropdownMenuItem(
                        value: 'DEACON_ORDINATION',
                        child: Text('رسامة الشمامسة'),
                      ),
                      DropdownMenuItem(
                        value: 'COMMUNION',
                        child: Text('سر التناول'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedTypeFilter = val);
                        _loadRecords();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'تحديث',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadRecords,
                ),
              ],
            ),
          ),

          // Content Area
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 12),
                        Text('حدث خطأ: $_errorMessage'),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadRecords,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  )
                : _records.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد سجلات مطابقة للبحث',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('نوع السر')),
                          DataColumn(label: Text('اسم صاحب السر')),
                          DataColumn(label: Text('التاريخ')),
                          DataColumn(label: Text('الكاهن المتمم')),
                          DataColumn(label: Text('الحالة')),
                          DataColumn(label: Text('رمز التحقق')),
                          DataColumn(label: Text('الإجراءات')),
                        ],
                        rows: _records.map((r) {
                          return DataRow(
                            cells: [
                              DataCell(Text(r.sacramentType.labelAr)),
                              DataCell(
                                Text(
                                  r.recipientNameAr,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${r.sacramentDate.year}-${r.sacramentDate.month.toString().padLeft(2, '0')}-${r.sacramentDate.day.toString().padLeft(2, '0')}',
                                ),
                              ),
                              DataCell(
                                Text(r.officiatingPriestName ?? 'غير محدد'),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: r.isRevoked
                                        ? Colors.red.shade50
                                        : Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: r.isRevoked
                                          ? Colors.red
                                          : Colors.green,
                                    ),
                                  ),
                                  child: Text(
                                    r.isRevoked ? 'ملغاة' : 'سارية',
                                    style: TextStyle(
                                      color: r.isRevoked
                                          ? Colors.red.shade900
                                          : Colors.green.shade900,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  r.verificationToken.length > 8
                                      ? '${r.verificationToken.substring(0, 8)}...'
                                      : r.verificationToken,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.visibility,
                                        color: Colors.blue,
                                      ),
                                      tooltip: 'عرض التفاصيل',
                                      onPressed: () =>
                                          SacramentDetailsDialog.show(
                                            context,
                                            r,
                                          ),
                                    ),
                                    if (!r.isRevoked)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.block,
                                          color: Colors.red,
                                        ),
                                        tooltip: 'إلغاء الشهادة',
                                        onPressed: () =>
                                            _onRevokeCertificate(r),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
