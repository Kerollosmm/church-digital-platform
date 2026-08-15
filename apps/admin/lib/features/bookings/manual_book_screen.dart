import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManualBookScreen extends StatefulWidget {
  const ManualBookScreen({super.key, this.db});
  final dynamic db;

  @override
  State<ManualBookScreen> createState() => _ManualBookScreenState();
}

class _ManualBookScreenState extends State<ManualBookScreen> {
  dynamic get _db => widget.db ?? Supabase.instance.client;

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
      final res = await _db.from('v_available_slots').select().eq('slot_status', 'AVAILABLE');
      final list = (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
      await _db.rpc('manual_book', params: {
        'p_slot_id': _selectedSlotId,
        'p_phone': _phoneController.text,
        'p_opt_in': _optIn,
        'p_notes': _notesController.text,
      });
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _message = 'تم الحجز اليدوي بنجاح';
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
                          color: _message!.startsWith('حدث خطأ') ? Colors.red : Colors.green,
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

