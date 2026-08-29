import 'package:flutter/material.dart';
import 'sacramental_models.dart';
import 'sacraments_admin_repository.dart';

class IssueSacramentDialog extends StatefulWidget {
  const IssueSacramentDialog({super.key, required this.repository});

  final SacramentsAdminRepository repository;

  static Future<SacramentalRecord?> show(
    BuildContext context,
    SacramentsAdminRepository repository,
  ) {
    return showDialog<SacramentalRecord>(
      context: context,
      builder: (ctx) => IssueSacramentDialog(repository: repository),
    );
  }

  @override
  State<IssueSacramentDialog> createState() => _IssueSacramentDialogState();
}

class _IssueSacramentDialogState extends State<IssueSacramentDialog> {
  final _formKey = GlobalKey<FormState>();

  SacramentType _selectedType = SacramentType.baptism;
  final _recipientNameController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _userIdController = TextEditingController();
  final _churchLocationController = TextEditingController(
    text: 'كنيسة السيدة العذراء والأنبا بيشوي',
  );
  final _registryBookController = TextEditingController();
  final _registryPageController = TextEditingController();
  final _registryEntryController = TextEditingController();
  final _godparentsController = TextEditingController();
  final _pdfPathController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  int? _selectedPriestId;
  List<Map<String, dynamic>> _priests = [];

  bool _isLoading = false;
  bool _isLoadingPriests = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPriests();
  }

  @override
  void dispose() {
    _recipientNameController.dispose();
    _nationalIdController.dispose();
    _userIdController.dispose();
    _churchLocationController.dispose();
    _registryBookController.dispose();
    _registryPageController.dispose();
    _registryEntryController.dispose();
    _godparentsController.dispose();
    _pdfPathController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadPriests() async {
    final res = await widget.repository.fetchPriests();
    if (!mounted) return;
    setState(() {
      _isLoadingPriests = false;
      res.fold(
        (failure) =>
            _errorMessage = 'فشل تحميل قائمة الكهنة: ${failure.message}',
        (priests) {
          _priests = priests;
          if (priests.isNotEmpty) {
            _selectedPriestId = priests.first['id'] as int?;
          }
        },
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final input = IssueSacramentInput(
      sacramentType: _selectedType,
      recipientNameAr: _recipientNameController.text.trim(),
      sacramentDate: _selectedDate,
      churchLocationAr: _churchLocationController.text.trim().isEmpty
          ? 'كنيسة السيدة العذراء والأنبا بيشوي'
          : _churchLocationController.text.trim(),
      recipientNationalId: _nationalIdController.text.trim().isEmpty
          ? null
          : _nationalIdController.text.trim(),
      recipientUserId: _userIdController.text.trim().isEmpty
          ? null
          : _userIdController.text.trim(),
      officiatingPriestId: _selectedPriestId,
      registryBookNumber: _registryBookController.text.trim().isEmpty
          ? null
          : _registryBookController.text.trim(),
      registryPageNumber: _registryPageController.text.trim().isEmpty
          ? null
          : _registryPageController.text.trim(),
      registryEntryNumber: _registryEntryController.text.trim().isEmpty
          ? null
          : _registryEntryController.text.trim(),
      godparentsAr: _godparentsController.text.trim().isEmpty
          ? null
          : _godparentsController.text.trim(),
      pdfStoragePath: _pdfPathController.text.trim().isEmpty
          ? null
          : _pdfPathController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    final res = await widget.repository.issueSacramentalCertificate(input);

    if (!mounted) return;

    setState(() => _isLoading = false);

    res.fold(
      (failure) {
        setState(
          () =>
              _errorMessage = 'حدث خطأ أثناء إصدار الشهادة: ${failure.message}',
        );
      },
      (record) {
        Navigator.of(context).pop(record);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650, maxHeight: 750),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.workspace_premium,
                      color: Colors.blue,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'إصدار شهادة سر كنسي جديدة',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(height: 24),
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<SacramentType>(
                          initialValue: _selectedType,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'نوع السر الكنسي *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.category),
                          ),
                          items: SacramentType.values
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.labelAr),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedType = val);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _recipientNameController,
                          decoration: const InputDecoration(
                            labelText: 'اسم صاحب السر باللغة العربية *',
                            hintText: 'مثال: كيرلس ميخائيل بطرس',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'يرجى إدخال اسم صاحب السر';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _nationalIdController,
                                decoration: const InputDecoration(
                                  labelText: 'الرقم القومي (اختياري)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.badge),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _userIdController,
                                decoration: const InputDecoration(
                                  labelText: 'معرف المستخدم UUID (اختياري)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.link),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _selectedDate,
                                    firstDate: DateTime(1900),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() => _selectedDate = picked);
                                  }
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'تاريخ إتمام السر *',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.calendar_today),
                                  ),
                                  child: Text(
                                    '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _isLoadingPriests
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : DropdownButtonFormField<int>(
                                      initialValue: _selectedPriestId,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'الكاهن المتمم للسر',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.person_pin),
                                      ),
                                      items: [
                                        const DropdownMenuItem<int>(
                                          value: null,
                                          child: Text('غير محدد'),
                                        ),
                                        ..._priests.map(
                                          (p) => DropdownMenuItem<int>(
                                            value: p['id'] as int,
                                            child: Text(
                                              p['name']?.toString() ?? '',
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        setState(() => _selectedPriestId = val);
                                      },
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _churchLocationController,
                          decoration: const InputDecoration(
                            labelText: 'مكان إتمام السر بالكنيسة *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.church),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _registryBookController,
                                decoration: const InputDecoration(
                                  labelText: 'رقم السجل / الدفتر',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _registryPageController,
                                decoration: const InputDecoration(
                                  labelText: 'رقم الصفحة',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _registryEntryController,
                                decoration: const InputDecoration(
                                  labelText: 'رقم القيد',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _godparentsController,
                          decoration: const InputDecoration(
                            labelText: 'العراب / الإشبين / الشهود',
                            hintText: 'مثال: الشماس يوسف حنا',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.people_outline),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _pdfPathController,
                          decoration: const InputDecoration(
                            labelText: 'مسار ملف الشهادة PDF في التخزين',
                            hintText: 'certificates/1/user_id/cert.pdf',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.picture_as_pdf),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _notesController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظات إدارية داخلية (سرية)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.notes),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _submit,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: const Text('إصدار وحفظ الشهادة'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
