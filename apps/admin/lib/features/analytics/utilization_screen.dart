import 'package:flutter/material.dart';

class UtilizationScreen extends StatefulWidget {
  const UtilizationScreen({super.key, required this.supabase});
  final dynamic supabase;

  @override
  State<UtilizationScreen> createState() => _UtilizationScreenState();
}

class _UtilizationScreenState extends State<UtilizationScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _data = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final res = await widget.supabase
          .from('v_analytics_utilization')
          .select();
      setState(() {
        _data = List<Map<String, dynamic>>.from(res as List);
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
      appBar: AppBar(title: const Text('Slot utilization')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data.isEmpty
              ? const Center(child: Text('No data yet'))
              : ListView.builder(
                  itemCount: _data.length,
                  itemBuilder: (context, index) {
                    final item = _data[index];
                    return ListTile(
                      title: Text(item['title_ar'] ?? ''),
                      subtitle: Text('Month: ${item['month']}'),
                      trailing: Text('${item['utilization_pct']}%'),
                    );
                  },
                ),
    );
  }
}
