import 'package:flutter/material.dart';
import 'analytics_repository.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, required this.repo});
  final AnalyticsRepository repo;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _data = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final res = await widget.repo.paymentRows();
      setState(() {
        _data = res.fold((f) => throw f, (rows) => rows);
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments Analytics'),
        actions: [
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.download),
            label: const Text('Export CSV'),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data.isEmpty
              ? const Center(child: Text('No data yet'))
              : ListView.builder(
                  itemCount: _data.length,
                  itemBuilder: (context, index) {
                    final item = _data[index];
                    return ListTile(
                      title: Text('Month: ${item['month']}'),
                      subtitle: Text('Paid: ${item['total_paid']} | Refunded: ${item['total_refunded']}'),
                      trailing: Text('Count: ${item['count_paid']}'),
                    );
                  },
                ),
    );
  }
}
