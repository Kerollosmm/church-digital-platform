import 'package:flutter/material.dart';
import 'analytics_repository.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key, required this.repo});
  final AnalyticsRepository repo;

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _data = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final res = await widget.repo.bookingRows();
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
        title: const Text('تحليلات الحجوزات'),
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
                          title: Text(item['title_ar'] ?? ''),
                          subtitle: Text('الشهر: ${item['month']}'),
                          trailing: Text('إجمالي الحجوزات: ${item['bookings_total']}'),
                        );
                      },
                    ),
    );
  }
}

