import 'package:flutter/material.dart';
import 'announcements_repository.dart';

class AnnouncementsAdminScreen extends StatefulWidget {
  const AnnouncementsAdminScreen({super.key, required this.repo});
  final AnnouncementsRepository repo;
  @override
  State<AnnouncementsAdminScreen> createState() =>
      _AnnouncementsAdminScreenState();
}

class _AnnouncementsAdminScreenState extends State<AnnouncementsAdminScreen> {
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

  Future<void> _create() async {
    final title = TextEditingController();
    final body = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعلان جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'العنوان'),
            ),
            TextField(
              controller: body,
              decoration: const InputDecoration(labelText: 'النص'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              if (title.text.trim().isEmpty || body.text.trim().isEmpty) return;
              final res = await widget.repo.create(
                titleAr: title.text.trim(),
                bodyAr: body.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              res.fold((f) => throw f, (created) {
                if (mounted) {
                  setState(() {
                    _rows = [...?_rows, created];
                  });
                }
              });
            },
            child: const Text('نشر'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعلانات')),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _rows?.length ?? 0,
              itemBuilder: (_, i) {
                final row = _rows![i];
                return ListTile(
                  title: Text(row['title_ar'] as String),
                  subtitle: Text(row['body_ar'] as String),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () async {
                      final id = row['id'] as int;
                      final res = await widget.repo.delete(id);
                      res.fold((f) => throw f, (_) {
                        if (mounted) {
                          setState(() {
                            _rows?.removeWhere((r) => r['id'] == id);
                          });
                        }
                      });
                    },
                  ),
                );
              },
            ),
    );
  }
}
