import 'package:flutter/material.dart';
import 'manual_book_repository.dart';

class ManualBookScreen extends StatefulWidget {
  const ManualBookScreen({super.key, required this.repo});
  final ManualBookRepository repo;

  @override
  State<ManualBookScreen> createState() => _ManualBookScreenState();
}

class _ManualBookScreenState extends State<ManualBookScreen> {
  ManualBookRepository get _repo => widget.repo;

  List<Map<String, dynamic>> _slots = [];
  int? _selectedSlotId;
  final _phoneController = TextEditingController();
  bool _optIn = false;
  final _notesController = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _fetchSlots();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _fetchSlots() async {
    try {
      final res = await _repo.availableSlots();
      final list = res.fold((f) => throw f, (rows) => rows);
      if (mounted) {
        setState(() {
          _slots = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _message = 'فشل في تحميل المواعيد: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_selectedSlotId == null) return;
    setState(() => _isSubmitting = true);
    try {
      final outcome = await _repo.manualBook(
        slotId: _selectedSlotId!,
        phone: _phoneController.text,
        optIn: _optIn,
        notes: _notesController.text,
      );
      if (outcome.isLeft) throw (outcome as dynamic).value;
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _message = 'تم تسجيل الحجز بنجاح';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _message = 'حدث خطأ: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('حجز يدوي'),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<dynamic>(
                      decoration: const InputDecoration(
                        labelText: 'الموعد المتاح',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _selectedSlotId,
                      items: _slots.map((slot) {
                        return DropdownMenuItem<dynamic>(
                          value: slot['slot_id'],
                          child: Text('${slot['title_ar']} - ${slot['starts_at']}'),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedSlotId = val as int?),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('phone_field'),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      key: const Key('opt_in_checkbox'),
                      title: const Text('تفعيل إشعارات واتساب / الرسائل'),
                      value: _optIn,
                      onChanged: (val) => setState(() => _optIn = val ?? false),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('notes_field'),
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      key: const Key('submit_button'),
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('تأكيد الحجز'),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _message!,
                        style: TextStyle(
                          color: (_message!.startsWith('حدث خطأ') || _message!.startsWith('فشل'))
                              ? Colors.red
                              : Colors.green,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
