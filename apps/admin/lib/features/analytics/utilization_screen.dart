import 'package:flutter/material.dart';
import 'analytics_repository.dart';

class UtilizationScreen extends StatefulWidget {
  const UtilizationScreen({super.key, required this.repo});
  final AnalyticsRepository repo;

  @override
  State<UtilizationScreen> createState() => _UtilizationScreenState();
}

class _UtilizationScreenState extends State<UtilizationScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _data = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final res = await widget.repo.utilizationRows();
    if (!mounted) return;
    setState(() {
      _loading = false;
      res.fold((f) => _error = f.message, (rows) => _data = rows);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('نسبة استخدام المواعيد')),
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
                          title: Text(item['title_ar'] ?? ''),
                          subtitle: Text('الشهر: ${item['month']}'),
                          trailing: Text('نسبة الاستخدام: ${item['utilization_pct']}%'),
                        );
                      },
                    ),
    );
  }
}

