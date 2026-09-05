import 'package:flutter/material.dart';
import '../../core/money_format.dart';
import 'payments_admin_repository.dart';
import '../../core/result.dart';

class PaymentsAdminScreen extends StatefulWidget {
  const PaymentsAdminScreen({super.key, required this.repo});
  final PaymentsAdminRepository repo;
  @override
  State<PaymentsAdminScreen> createState() => _PaymentsAdminScreenState();
}

class _PaymentsAdminScreenState extends State<PaymentsAdminScreen> {
  late Future<List<Map<String, dynamic>>> _rows;

  @override
  void initState() {
    super.initState();
    _rows = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async =>
      (await widget.repo.list()).fold(
        (f) => throw f,
        (rows) => List<Map<String, dynamic>>.from(
          rows.map((r) => Map<String, dynamic>.from(r)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المدفوعات')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _rows,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final err = snapshot.error;
            final msg = err is Failure
                ? err.message
                : 'حدث خطأ غير متوقع، يرجى المحاولة لاحقاً';
            return Center(child: Text(msg));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              return ListTile(
                title: Text('دفع #${r['id']} — ${formatEgp((r['amount'] as num).toInt())}'),
                subtitle: Text('حجز ${r['booking_id']} — ${r['status']}'),
                trailing: Text(r['gateway_ref']?.toString() ?? ''),
              );
            },
          );
        },
      ),
    );
  }
}
