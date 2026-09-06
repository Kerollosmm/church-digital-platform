import 'package:flutter/material.dart';
import 'emergency_override_repository.dart';

class EmergencyOverrideScreen extends StatefulWidget {
  const EmergencyOverrideScreen({super.key, required this.repo});
  final EmergencyOverrideRepository repo;

  @override
  State<EmergencyOverrideScreen> createState() =>
      _EmergencyOverrideScreenState();
}

class _EmergencyOverrideScreenState extends State<EmergencyOverrideScreen> {
  final _bookingIdController = TextEditingController();
  List<Map<String, dynamic>> _slots = [];
  int? _selectedNewSlotId;
  bool _refund = false;

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
    _bookingIdController.dispose();
    super.dispose();
  }

  Future<void> _fetchSlots() async {
    try {
      final res = await widget.repo.availableSlots();
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
    final bookingId = int.tryParse(_bookingIdController.text);
    if (bookingId == null || _selectedNewSlotId == null) return;
    setState(() => _isSubmitting = true);
    try {
      final outcome = await widget.repo.override(
        bookingId: bookingId,
        newSlotId: _selectedNewSlotId!,
        refund: _refund,
      );
      outcome.fold((f) => throw f, (_) {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
            _message = 'تم تعديل الطوارئ بنجاح';
          });
        }
      });
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
      appBar: AppBar(title: const Text('طوارئ / نقل حجز')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('booking_id_field'),
                      controller: _bookingIdController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'رقم الحجز الحالي',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<dynamic>(
                      decoration: const InputDecoration(
                        labelText: 'الموعد الجديد',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _selectedNewSlotId,
                      items: _slots.map((slot) {
                        return DropdownMenuItem<dynamic>(
                          value: slot['slot_id'],
                          child: Text(
                            '${slot['title_ar']} - ${slot['starts_at']}',
                          ),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setState(() => _selectedNewSlotId = val as int?),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      key: const Key('refund_toggle'),
                      title: const Text('استرداد المبلغ / إرجاع الرسوم'),
                      value: _refund,
                      onChanged: (val) => setState(() => _refund = val),
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
                          : const Text('تأكيد تعديل الطوارئ'),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _message!,
                        style: TextStyle(
                          color: _message!.startsWith('حدث خطأ')
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
