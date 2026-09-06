import 'package:flutter/material.dart';
import '../../core/money_format.dart';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final res = await widget.repo.paymentRows();
    if (!mounted) return;
    setState(() {
      _loading = false;
      res.fold((f) => _error = f.message, (rows) => _data = rows);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تحليلات المدفوعات'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                )
              : _data.isEmpty
                  ? const Center(child: Text('لا توجد بيانات بعد'))
                  : ListView.builder(
                      itemCount: _data.length,
                      itemBuilder: (context, index) {
                        final item = _data[index];
                        return ListTile(
                          title: Text('الشهر: ${item['month']}'),
                          subtitle: Text(
                            'مدفوع: ${formatEgp((item['total_paid'] as num?)?.toInt() ?? 0)} | مسترد: ${formatEgp((item['total_refunded'] as num?)?.toInt() ?? 0)}',
                          ),
                          trailing: Text('عدد العمليات: ${item['count_paid']}'),
                        );
                      },
                    ),
    );
  }
}

