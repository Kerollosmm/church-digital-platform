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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final res = await widget.repo.bookingRows();
      setState(() {
        _data = res.fold((f) => throw f, (rows) => rows);
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('bookingRows failed: $e\n$st');
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookings Analytics'),
        actions: [
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.download),
            label: const Text('Export CSV'),
          ),
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
                  title: Text(item['title_ar'] ?? ''),
                  subtitle: Text('Month: ${item['month']}'),
                  trailing: Text('Total: ${item['bookings_total']}'),
                );
              },
            ),
    );
  }
}
