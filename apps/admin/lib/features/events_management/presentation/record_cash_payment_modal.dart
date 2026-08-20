import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_events_provider.dart';
import '../data/admin_event_repository.dart';
import '../domain/admin_event_models.dart';

class RecordCashPaymentModal extends ConsumerStatefulWidget {
  final AdminEventBookingModel booking;

  const RecordCashPaymentModal({super.key, required this.booking});

  @override
  ConsumerState<RecordCashPaymentModal> createState() => _RecordCashPaymentModalState();
}

class _RecordCashPaymentModalState extends ConsumerState<RecordCashPaymentModal> {
  final _amountEgpController = TextEditingController();
  final _receiptRefController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('تسجيل إيصال سداد نقدي للحجز #${widget.booking.id}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الإجمالي: ${widget.booking.totalPriceEgp.toStringAsFixed(0)} ج.م'),
            Text('المدفوع حالياً: ${widget.booking.paidAmountEgp.toStringAsFixed(0)} ج.م'),
            Text('المتبقي: ${widget.booking.remainingEgp.toStringAsFixed(0)} ج.م',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            const Divider(),
            TextField(
              controller: _amountEgpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'المبلغ المستلم نقدياً (بالجنيه المصري)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _receiptRefController,
              decoration: const InputDecoration(
                labelText: 'رقم الإيصال / المرجع الورقي',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'ملاحظات دفترية',
                border: OutlineInputBorder(),
              ),
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
          onPressed: _isSubmitting
              ? null
              : () async {
                  final egpText = _amountEgpController.text.trim();
                  final amountEgp = double.tryParse(egpText) ?? 0;
                  if (amountEgp <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يرجى إدخال مبلغ صحيح بالجنيه')),
                    );
                    return;
                  }

                  final amountPiastres = (amountEgp * 100).round();
                  setState(() => _isSubmitting = true);

                  try {
                    await ref.read(adminEventRepositoryProvider).recordCashPayment(
                          bookingId: widget.booking.id,
                          amountPiastres: amountPiastres,
                          receiptRef: _receiptRefController.text.trim(),
                          notes: _notesController.text.trim(),
                        );
                    if (mounted) {
                      ref.invalidate(eventQueueProvider);
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تسجيل الإيصال النقدي وتحديث الحساب بنجاح')),
                      );
                    }
                  } catch (e) {
                    setState(() => _isSubmitting = false);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('فشل التسجيل: $e')),
                      );
                    }
                  }
                },
          child: _isSubmitting ? const CircularProgressIndicator() : const Text('إصدار الإيصال النقدي'),
        ),
      ],
    );
  }
}
