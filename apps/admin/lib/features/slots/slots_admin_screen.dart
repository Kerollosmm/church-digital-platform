import 'package:flutter/material.dart';
import '../../core/money_format.dart';
import 'slots_admin_repository.dart';

class SlotsAdminScreen extends StatefulWidget {
  const SlotsAdminScreen({super.key, required this.repo});
  final SlotsAdminRepository repo;
  @override
  State<SlotsAdminScreen> createState() => _SlotsAdminScreenState();
}

class _SlotsAdminScreenState extends State<SlotsAdminScreen> {
  List<Map<String, dynamic>>? _rows;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await widget.repo.list();
    if (!mounted) return;
    setState(() {
      res.fold(
        (f) {
          _error = f.message;
          _rows = null;
        },
        (rows) {
          _error = null;
          _rows = List<Map<String, dynamic>>.from(
            rows.map((r) => Map<String, dynamic>.from(r)),
          );
        },
      );
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المواعيد')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              ),
            )
          : ListView.builder(
              itemCount: _rows?.length ?? 0,
              itemBuilder: (_, i) {
                final r = _rows![i];
                return ListTile(
                  title: Text('${r['starts_at']} — ${formatEgp((r['price'] as num?)?.toInt() ?? 0)}'),
                  subtitle: Text('سعة ${r['capacity']} — ${r['status']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.lock_outline),
                    tooltip: 'إغلاق',
                    onPressed: () async {
                      final id = r['id'] as int;
                      final res = await widget.repo.closeSlot(id);
                      if (!mounted) return;
                      res.fold(
                        (f) => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(f.message)),
                        ),
                        (_) {
                          setState(() {
                            r['status'] = 'CLOSED';
                          });
                        },
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
