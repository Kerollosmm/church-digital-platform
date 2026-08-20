import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/event_models.dart';
import '../data/event_booking_repository.dart';

class EventBookingDetailScreen extends ConsumerWidget {
  final EventBookingModel booking;

  const EventBookingDetailScreen({super.key, required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text('حجز مناسبة رقم #${booking.id}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('حالة الطلب:', style: TextStyle(fontSize: 16)),
                        Chip(
                          label: Text(_statusArabic(booking.status)),
                          backgroundColor: _statusColor(booking.status),
                        ),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('الإجمالي:'),
                        Text('${booking.totalPriceEgp.toStringAsFixed(0)} ج.م',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('المدفوع:'),
                        Text('${booking.paidAmountEgp.toStringAsFixed(0)} ج.م',
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    if (booking.remainingEgp > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('المتبقي:'),
                          Text('${booking.remainingEgp.toStringAsFixed(0)} ج.م',
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (booking.status == 'PENDING_PAYMENT' && booking.remainingEgp > 0)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.payment),
                  label: const Text('دفع المتبقي أونلاين (Paymob)', style: TextStyle(fontSize: 18)),
                  onPressed: () async {
                    try {
                      final url = await ref
                          .read(eventBookingRepositoryProvider)
                          .initiatePaymobCheckout(booking.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('رابط الدفع: $url')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('خطأ: $e')),
                        );
                      }
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _statusArabic(String status) {
    switch (status) {
      case 'SUBMITTED':
        return 'قيد المراجعة';
      case 'PENDING_PAYMENT':
        return 'مقبول - بانتظار الدفع';
      case 'CONFIRMED':
        return 'مؤكد';
      case 'PAID':
        return 'مدفوع بالكامل';
      case 'PARTIALLY_PAID':
        return 'مدفوع جزئياً';
      case 'REJECTED':
        return 'مرفوض';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'SUBMITTED':
        return Colors.amber.shade200;
      case 'PENDING_PAYMENT':
        return Colors.orange.shade200;
      case 'CONFIRMED':
      case 'PAID':
        return Colors.green.shade200;
      case 'REJECTED':
        return Colors.red.shade200;
      default:
        return Colors.grey.shade200;
    }
  }
}
