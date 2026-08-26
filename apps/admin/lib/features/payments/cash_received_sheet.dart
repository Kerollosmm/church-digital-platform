import 'package:flutter/material.dart';
import 'payments_admin_repository.dart';

/// Modal bottom sheet for staff to record direct in-person cash payment.
class CashReceivedSheet extends StatefulWidget {
  const CashReceivedSheet({
    super.key,
    required this.repository,
    required this.bookingId,
    required this.initialAmount,
    this.onSuccess,
  });

  final PaymentsAdminRepository repository;
  final int bookingId;
  final int initialAmount;
  final VoidCallback? onSuccess;

  static Future<void> show(
    BuildContext context, {
    required PaymentsAdminRepository repository,
    required int bookingId,
    required int initialAmount,
    VoidCallback? onSuccess,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => CashReceivedSheet(
        repository: repository,
        bookingId: bookingId,
        initialAmount: initialAmount,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<CashReceivedSheet> createState() => _CashReceivedSheetState();
}

class _CashReceivedSheetState extends State<CashReceivedSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.initialAmount.toString(),
    );
    _noteController = TextEditingController(text: 'استلام نقدي بالخزينة');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'يرجى إدخال مبلغ صحيح أكبر من الصفر');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await widget.repository.markCashReceived(
      widget.bookingId,
      amount,
      collectorNote: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _loading = false);

    res.fold((fail) => setState(() => _error = fail.message), (_) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تسجيل استلام النقدية للحجز #${widget.bookingId} بنجاح',
          ),
          backgroundColor: Colors.green,
        ),
      );
      widget.onSuccess?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'استلام دفع نقدي — حجز #${widget.bookingId}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withAlpha(100)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'المبلغ المحصل (ج.م):',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                prefixText: 'EGP ',
                prefixStyle: const TextStyle(color: Colors.amber),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'ملاحظة المحصل:',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _noteController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                hintText: 'اسم المحصل أو رقم إيصال الخزينة',
                hintStyle: const TextStyle(color: Colors.white38),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline, color: Colors.black),
              label: Text(
                _loading ? 'جاري التسجيل...' : 'تأكيد استلام النقدية',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE2B755),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
