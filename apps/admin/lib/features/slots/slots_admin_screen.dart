import 'package:flutter/material.dart';
import 'slots_admin_repository.dart';
import '../../core/result.dart';

class SlotsAdminScreen extends StatefulWidget {
  const SlotsAdminScreen({super.key, required this.repo});
  final SlotsAdminRepository repo;
  @override
  State<SlotsAdminScreen> createState() => _SlotsAdminScreenState();
}

class _SlotsAdminScreenState extends State<SlotsAdminScreen> {
  List<Map<String, dynamic>>? _rows;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await widget.repo.list();
    if (mounted) {
      setState(() {
        _rows = res.fold(
          (f) => throw f,
          (rows) => List<Map<String, dynamic>>.from(
            rows.map((r) => Map<String, dynamic>.from(r)),
          ),
        );
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المواعيد')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _rows?.length ?? 0,
              itemBuilder: (_, i) {
                final r = _rows![i];
                return ListTile(
                  title: Text('${r['starts_at']} — ${r['price']} جنيه'),
                  subtitle: Text('سعة ${r['capacity']} — ${r['status']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.lock_outline),
                    tooltip: 'إغلاق',
                    onPressed: () async {
                      final id = r['id'] as int;
                      unwrapOrThrow(await widget.repo.closeSlot(id));
                      if (mounted) {
                        setState(() {
                          r['status'] = 'CLOSED';
                        });
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}
