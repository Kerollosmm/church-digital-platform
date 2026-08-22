import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/admin_auth_provider.dart';
import 'models/payout_channel.dart';
import 'payments_admin_repository.dart';

/// Screen for viewing and configuring church payout channels (Vodafone Cash, InstaPay, Cash).
/// Accessible in read-only mode to ADMIN, editable only by SUPER_ADMIN.
class PayoutsConfigScreen extends ConsumerStatefulWidget {
  const PayoutsConfigScreen({
    super.key,
    this.repo,
    this.isSuperAdminOverride,
  });

  final PaymentsAdminRepository? repo;
  final bool? isSuperAdminOverride;

  @override
  ConsumerState<PayoutsConfigScreen> createState() => _PayoutsConfigScreenState();
}

class _PayoutsConfigScreenState extends ConsumerState<PayoutsConfigScreen> {
  late final PaymentsAdminRepository _repo;
  List<PayoutChannel> _channels = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = widget.repo ?? PaymentsAdminRepository(Supabase.instance.client);
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await _repo.listPayoutChannels();
    if (!mounted) return;

    res.fold(
      (fail) => setState(() {
        _loading = false;
        _error = fail.message;
      }),
      (channels) => setState(() {
        _loading = false;
        _channels = channels;
      }),
    );
  }

  Future<void> _editChannel(PayoutChannel channel) async {
    final nameCtrl = TextEditingController(text: channel.displayNameAr);
    final numberCtrl = TextEditingController(text: channel.accountNumber);
    final holderCtrl = TextEditingController(text: channel.holderName);
    String? dialogError;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('تعديل بيانات ${channel.displayNameAr}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (dialogError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(40),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(dialogError!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                    ),
                  ],
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'اسم الوسيلة بالعربية'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: numberCtrl,
                    decoration: const InputDecoration(labelText: 'رقم المحفظة / الحساب'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: holderCtrl,
                    decoration: const InputDecoration(labelText: 'اسم صاحب المحفظة / الحساب'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (nameCtrl.text.trim().isEmpty || numberCtrl.text.trim().isEmpty) {
                          setDialogState(() => dialogError = 'يرجى ملء جميع الحقول المطلوبة');
                          return;
                        }

                        setDialogState(() {
                          saving = true;
                          dialogError = null;
                        });

                        final updated = PayoutChannel(
                          id: channel.id,
                          channel: channel.channel,
                          displayNameAr: nameCtrl.text.trim(),
                          accountNumber: numberCtrl.text.trim(),
                          holderName: holderCtrl.text.trim(),
                        );

                        final res = await _repo.upsertPayoutChannel(updated);
                        if (!mounted) return;

                        res.fold(
                          (fail) => setDialogState(() {
                            saving = false;
                            dialogError = fail.message;
                          }),
                          (_) {
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم تحديث بيانات وسيلة الدفع بنجاح'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _loadChannels();
                          },
                        );
                      },
                child: saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('حفظ التعديلات'),
              ),
            ],
          ),
        ),
      ),
    );

    nameCtrl.dispose();
    numberCtrl.dispose();
    holderCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isSuperAdmin = widget.isSuperAdminOverride ?? false;
    if (widget.isSuperAdminOverride == null) {
      try {
        final authState = ref.watch(adminAuthProvider);
        isSuperAdmin = authState.role == 'SUPER_ADMIN';
      } catch (_) {
        isSuperAdmin = false;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات حسابات ومحافظ التحصيل'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: _loadChannels,
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _loadChannels, child: const Text('إعادة المحاولة')),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (!isSuperAdmin)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.amber.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.withAlpha(80)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.amber),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'عرض تفاصيل الحسابات متاح للقراءة فقط. تعديل أرقام المحافظ مقتصر على الإدارة العليا (SUPER_ADMIN).',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ..._channels.map((ch) => Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            ch.channel == 'CASH'
                                                ? Icons.payments_outlined
                                                : Icons.account_balance_wallet_outlined,
                                            color: const Color(0xFFE2B755),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            ch.displayNameAr,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (isSuperAdmin)
                                        IconButton(
                                          icon: const Icon(Icons.edit, color: Colors.amber),
                                          tooltip: 'تعديل بيانات الحساب',
                                          onPressed: () => _editChannel(ch),
                                        ),
                                    ],
                                  ),
                                  const Divider(height: 20),
                                  Row(
                                    children: [
                                      const Text('رقم الحساب / المحفظة: ', style: TextStyle(color: Colors.white60)),
                                      Text(
                                        ch.accountNumber.isEmpty ? 'غير محدد' : ch.accountNumber,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Text('اسم المستلم / صاحب الحساب: ', style: TextStyle(color: Colors.white60)),
                                      Text(
                                        ch.holderName.isEmpty ? 'غير محدد' : ch.holderName,
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          )),
                    ],
                  ),
      ),
    );
  }
}
