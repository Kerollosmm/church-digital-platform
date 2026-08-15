import 'package:flutter/material.dart';

class PaymentsAdminScreen extends StatefulWidget {
  const PaymentsAdminScreen({super.key, required this.db});
  final dynamic db;
  @override
  State<PaymentsAdminScreen> createState() => _PaymentsAdminScreenState();
}

class _PaymentsAdminScreenState extends State<PaymentsAdminScreen> {
  late Future<List<Map<String, dynamic>>> _rows;
  @override
  void initState() { super.initState(); _rows = _load(); }
  Future<List<Map<String, dynamic>>> _load() async =>
      ((await widget.db.from('payments').select().order('created_at', ascending: false)) as List)
          .map((r) => Map<String, dynamic>.from(r as Map)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المدفوعات')),
      body: FutureBuilder(
        future: _rows,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data!;
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              return ListTile(
                title: Text('دفع #${r['id']} — ${r['amount']} جنيه'),
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
