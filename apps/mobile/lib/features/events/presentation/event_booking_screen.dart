import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'events_provider.dart';

class EventBookingScreen extends ConsumerStatefulWidget {
  const EventBookingScreen({super.key});

  @override
  ConsumerState<EventBookingScreen> createState() => _EventBookingScreenState();
}

class _EventBookingScreenState extends ConsumerState<EventBookingScreen> {
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final _notesController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(eventBookingNotifierProvider);
    final extrasAsync = ref.watch(extraServicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(state.selectedEventType?.nameAr ?? 'تفاصيل حجز المناسبة'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('السعر الأساسي:', style: TextStyle(fontSize: 16)),
                    Text(
                      '${(state.basePricePiastres / 100.0).toStringAsFixed(0)} ج.م',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('الموعد المطلوب:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _selectedDate == null
                          ? 'اختر التاريخ'
                          : '${_selectedDate!.year}-${_selectedDate!.month}-${_selectedDate!.day}',
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                        _updateDateTime();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.access_time),
                    label: Text(
                      _selectedTime == null ? 'اختر الوقت' : _selectedTime!.format(context),
                    ),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: const TimeOfDay(hour: 12, minute: 0),
                      );
                      if (picked != null) {
                        setState(() => _selectedTime = picked);
                        _updateDateTime();
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('الخدمات الإضافية (اختياري):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            extrasAsync.when(
              data: (extras) {
                return Column(
                  children: extras.map((extra) {
                    final selectedExtra = state.selectedExtras[extra.id];
                    final isSelected = selectedExtra != null;

                    return CheckboxListTile(
                      title: Text(extra.nameAr),
                      subtitle: Text('${extra.unitPriceEgp.toStringAsFixed(0)} ج.م'),
                      value: isSelected,
                      onChanged: (val) {
                        ref.read(eventBookingNotifierProvider.notifier).toggleExtra(extra, val ?? false);
                      },
                    );
                  }).toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('فشل تحميل الخدمات: $err'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'ملاحظات إضافية',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                ref.read(eventBookingNotifierProvider.notifier).setNotes(val);
              },
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الإجمالي التقديري:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                    '${state.grandTotalEgp.toStringAsFixed(0)} ج.م',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (state.error != null) ...[
              Text(state.error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: state.isSubmitting
                    ? null
                    : () async {
                        final bookingId = await ref
                            .read(eventBookingNotifierProvider.notifier)
                            .submitBooking();
                        if (bookingId != null && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تم ارسال طلب الحجز بنجاح (رقم $bookingId)')),
                          );
                          Navigator.of(context).pop();
                        }
                      },
                child: state.isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('إرسال طلب الحجز والمراجعة', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateDateTime() {
    if (_selectedDate != null && _selectedTime != null) {
      final dt = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
      ref.read(eventBookingNotifierProvider.notifier).setRequestedTime(dt);
    }
  }
}
