import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_events_provider.dart';
import 'event_review_dialog.dart';
import 'record_cash_payment_modal.dart';
import '../data/admin_event_repository.dart';

class EventBookingsQueueScreen extends ConsumerWidget {
  const EventBookingsQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(eventQueueProvider);
    final activeFilter = ref.watch(adminEventFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('مكتب مراجعة وحجوزات المناسبات الكنسية'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(eventQueueProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip(ref, null, 'الكل', activeFilter),
                  _filterChip(ref, 'SUBMITTED', 'قيد المراجعة', activeFilter),
                  _filterChip(ref, 'PENDING_PAYMENT', 'بانتظار الدفع', activeFilter),
                  _filterChip(ref, 'CONFIRMED', 'مؤكد', activeFilter),
                  _filterChip(ref, 'PAID', 'مدفوع بالكامل', activeFilter),
                  _filterChip(ref, 'PARTIALLY_PAID', 'مدفوع جزئياً', activeFilter),
                  _filterChip(ref, 'REJECTED', 'مرفوض', activeFilter),
                ],
              ),
            ),
          ),
          Expanded(
            child: queueAsync.when(
              data: (bookings) {
                if (bookings.isEmpty) {
                  return const Center(child: Text('لا توجد طلبات مناسبات في القائمة'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: bookings.length,
                  itemBuilder: (context, index) {
                    final b = bookings[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(
                          'طلب مناسبة #${b.id} - ${b.userName ?? "مواطن"}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'الهاتف: ${b.userPhone ?? "غ/م"} | الإجمالي: ${b.totalPriceEgp.toStringAsFixed(0)} ج.م | المدفوع: ${b.paidAmountEgp.toStringAsFixed(0)} ج.م',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(label: Text(b.status)),
                            const SizedBox(width: 8),
                            if (b.status == 'SUBMITTED')
                              IconButton(
                                icon: const Icon(Icons.rate_review, color: Colors.indigo),
                                tooltip: 'مراجعة وتخصيص قاعة',
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => EventReviewDialog(booking: b),
                                  );
                                },
                              ),
                            if (b.status == 'PENDING_PAYMENT' || b.status == 'PARTIALLY_PAID')
                              IconButton(
                                icon: const Icon(Icons.payments, color: Colors.green),
                                tooltip: 'تسجيل دفع نقدي',
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => RecordCashPaymentModal(booking: b),
                                  );
                                },
                              ),
                            if (b.status == 'SUBMITTED')
                              IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.red),
                                tooltip: 'رفض الطلب',
                                onPressed: () => _promptReject(context, ref, b.id),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('حدث خطأ أثناء جلب الطلبات: $err')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(WidgetRef ref, String? value, String label, String? activeFilter) {
    final isSelected = activeFilter == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          ref.read(adminEventFilterProvider.notifier).setFilter(value);
        },
      ),
    );
  }

  void _promptReject(BuildContext context, WidgetRef ref, int bookingId) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('رفض طلب المناسبة #$bookingId'),
          content: TextField(
            controller: reasonController,
            decoration: const InputDecoration(
              labelText: 'سبب الرفض (إجباري)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) return;
                try {
                  await ref.read(adminEventRepositoryProvider).rejectBooking(
                        bookingId: bookingId,
                        reason: reason,
                      );
                  ref.invalidate(eventQueueProvider);
                  Navigator.of(ctx).pop();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('خطأ: $e')),
                  );
                }
              },
              child: const Text('تأكيد الرفض'),
            ),
          ],
        );
      },
    );
  }
}
