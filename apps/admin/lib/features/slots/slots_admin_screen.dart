import 'package:flutter/material.dart';

class SlotsAdminScreen extends StatefulWidget {
  const SlotsAdminScreen({super.key, required this.db});
  final dynamic db;
  @override
  State<SlotsAdminScreen> createState() => _SlotsAdminScreenState();
}

class _SlotsAdminScreenState extends State<SlotsAdminScreen> {
  late Future<List<Map<String, dynamic>>> _rows;
  @override
  void initState() { super.initState(); _rows = _load(); }
  Future<List<Map<String, dynamic>>> _load() async =>
      ((await widget.db.from('service_slots').select()) as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المواعيد')),
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
                title: Text('${r['starts_at']} — ${r['price']} جنيه'),
                subtitle: Text('سعة ${r['capacity']} — ${r['status']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.lock_outline),
                  tooltip: 'إغلاق',
                  onPressed: () async {
                    await widget.db.from('service_slots').update({'status': 'CLOSED'}).eq('id', r['id']);
                    final next = _load();
                    setState(() {
                      _rows = next;
                    });
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
