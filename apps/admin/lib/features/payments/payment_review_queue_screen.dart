import 'package:flutter/material.dart';
import '../../core/result.dart';
import 'models/payment_proof_review.dart';
import 'payments_admin_repository.dart';

class PaymentReviewQueueScreen extends StatefulWidget {
  const PaymentReviewQueueScreen({super.key, required this.repo});
  final PaymentsAdminRepository repo;

  @override
  State<PaymentReviewQueueScreen> createState() => _PaymentReviewQueueScreenState();
}

class _PaymentReviewQueueScreenState extends State<PaymentReviewQueueScreen> {
  late Future<List<PaymentProofReview>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = _fetch();
    });
  }

  Future<List<PaymentProofReview>> _fetch() async {
    final result = await widget.repo.listPendingProofs();
    return unwrapOrThrow(result);
  }

  Future<void> _handleApprove(PaymentProofReview proof) async {
    String? collectorNote;
    if (proof.channel == 'CASH') {
      final noteController = TextEditingController();
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تأكيد استلام النقدية'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('المبلغ: ${proof.amountClaimed} جنيه (حجز #${proof.bookingId})'),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'اسم مستلم النقدية / ملاحظة التحصيل',
                  hintText: 'مثال: استلمها الشماس يوسف بالخزينة',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('تأكيد الدفع'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      collectorNote = noteController.text.trim().isNotEmpty ? noteController.text.trim() : null;
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تأكيد قبول إثبات الدفع'),
          content: Text(
            'هل تم التحقق من استلام مبلغ ${proof.amountClaimed} جنيه على حساب الكنيسة بالمرجع ${proof.referenceNumber}؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('قبول وتأكيد الحجز'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final res = await widget.repo.approveProof(proof.id, collectorNote: collectorNote);
    if (!mounted) return;

    if (res.isRight) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم قبول إثبات الدفع للحجز #${proof.bookingId} بنجاح')),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.leftOrNull?.message ?? 'تعذر قبول الإثبات')),
      );
    }
  }

  Future<void> _handleReject(PaymentProofReview proof) async {
    const reasons = [
      {'code': 'BAD_REQUEST', 'label': 'البيانات غير متطابقة مع كشف الحساب'},
      {'code': 'FALLBACK', 'label': 'صورة الإشعار غير واضحة أو غير مكتملة'},
      {'code': 'UPSTREAM_ERROR', 'label': 'لم يتم العثور على المعاملة بالمحفظة'},
    ];

    String selectedCode = reasons.first['code']!;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('رفض إثبات الدفع'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('حجز #${proof.bookingId} — مبلغ: ${proof.amountClaimed} جنيه'),
              const SizedBox(height: 12),
              const Text('سبب الرفض (سيظهر للمخدوم لإعادة الإرسال):', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: selectedCode,
                items: reasons
                    .map((r) => DropdownMenuItem(
                          value: r['code'],
                          child: Text(r['label']!),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedCode = val);
                },
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('تأكيد الرفض', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    final res = await widget.repo.rejectProof(proof.id, selectedCode);
    if (!mounted) return;

    if (res.isRight) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم رفض إثبات الدفع للحجز #${proof.bookingId}')),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.leftOrNull?.message ?? 'تعذر رفض الإثبات')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مراجعة إثباتات الدفع'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'تحديث القائمة',
          ),
        ],
      ),
      body: FutureBuilder<List<PaymentProofReview>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('حدث خطأ: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                ],
              ),
            );
          }

          final proofs = snapshot.data ?? [];
          if (proofs.isEmpty) {
            return const Center(
              child: Text(
                'لا توجد إثباتات دفع قيد المراجعة حالياً',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: proofs.length,
            itemBuilder: (context, index) {
              final p = proofs[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'حجز #${p.bookingId}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Chip(
                            label: Text(p.channelDisplayName),
                            backgroundColor: Colors.blue.shade50,
                          ),
                        ],
                      ),
                      const Divider(),
                      const SizedBox(height: 6),
                      Text('المبلغ المطلوب: ${p.amountClaimed} جنيه', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('رقم الهاتف المحول منه: ${p.senderPhone}'),
                      Text('رقم المعاملة / المرجع: ${p.referenceNumber}'),
                      if (p.imagePath != null) ...[
                        const SizedBox(height: 8),
                        Text('مسار صورة الإشعار: ${p.imagePath}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.close, color: Colors.red),
                            label: const Text('رفض', style: TextStyle(color: Colors.red)),
                            onPressed: () => _handleReject(p),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.check),
                            label: const Text('قبول وتأكيد'),
                            onPressed: () => _handleApprove(p),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
