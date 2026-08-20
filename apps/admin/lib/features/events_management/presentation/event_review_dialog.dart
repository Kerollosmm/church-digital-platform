import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_events_provider.dart';
import '../data/admin_event_repository.dart';
import '../domain/admin_event_models.dart';

class EventReviewDialog extends ConsumerStatefulWidget {
  final AdminEventBookingModel booking;

  const EventReviewDialog({super.key, required this.booking});

  @override
  ConsumerState<EventReviewDialog> createState() => _EventReviewDialogState();
}

class _EventReviewDialogState extends ConsumerState<EventReviewDialog> {
  int? _selectedVenueId;
  DateTime? _selectedStart;
  int _durationMinutes = 120;
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final venuesAsync = ref.watch(venuesProvider);

    return AlertDialog(
      title: Text('مراجعة وتأكيد طلب المناسبة #${widget.booking.id}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الاسم: ${widget.booking.userName ?? "غير معروف"}'),
            Text('الهاتف: ${widget.booking.userPhone ?? "غير متوفر"}'),
            Text('الإجمالي: ${widget.booking.totalPriceEgp.toStringAsFixed(0)} ج.م'),
            const Divider(),
            const Text('تخصيص القاعة / المذبح:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            venuesAsync.when(
              data: (venues) {
                if (venues.isEmpty) return const Text('لا توجد قاعات متوفرة');
                return DropdownButtonFormField<int>(
                  value: _selectedVenueId,
                  hint: const Text('اختر القاعة / المباشر'),
                  items: venues.map((v) {
                    return DropdownMenuItem<int>(
                      value: v.id,
                      child: Text('${v.nameAr} (سعة ${v.capacity})'),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedVenueId = val),
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (err, _) => Text('خطأ: $err'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text(_selectedStart == null
                  ? 'اختر موعد البدء التأكيدي'
                  : _selectedStart!.toIso8601String().substring(0, 16)),
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null && mounted) {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 14, minute: 0),
                  );
                  if (time != null) {
                    setState(() {
                      _selectedStart = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  }
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: (_selectedVenueId == null || _selectedStart == null || _isSubmitting)
              ? null
              : () async {
                  setState(() => _isSubmitting = true);
                  try {
                    await ref.read(adminEventRepositoryProvider).confirmBooking(
                          bookingId: widget.booking.id,
                          venueId: _selectedVenueId!,
                          confirmedStart: _selectedStart!,
                          durationMinutes: _durationMinutes,
                        );
                    if (mounted) {
                      ref.invalidate(eventQueueProvider);
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تأكيد الطلب وحجز القاعة بنجاح')),
                      );
                    }
                  } catch (e) {
                    setState(() => _isSubmitting = false);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('فشل التأكيد: $e')),
                      );
                    }
                  }
                },
          child: _isSubmitting ? const CircularProgressIndicator() : const Text('تأكيد وحجز القاعة'),
        ),
      ],
    );
  }
}
