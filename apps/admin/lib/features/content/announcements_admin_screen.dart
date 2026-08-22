import 'package:flutter/material.dart';
import 'announcements_repository.dart';

class AnnouncementsAdminScreen extends StatefulWidget {
  const AnnouncementsAdminScreen({super.key, required this.repo});
  final AnnouncementsRepository repo;
  @override
  State<AnnouncementsAdminScreen> createState() => _AnnouncementsAdminScreenState();
}

class _AnnouncementsAdminScreenState extends State<AnnouncementsAdminScreen> {
  late Future<List<Map<String, dynamic>>> _rows;
  @override
  void initState() {
    super.initState();
    _rows = _load();
  }
  Future<List<Map<String, dynamic>>> _load() async =>
      (await widget.repo.list()).fold((f) => throw f, (rows) => rows);

  Future<void> _create() async {
    final title = TextEditingController();
    final body = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعلان جديد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان')),
          TextField(controller: body, decoration: const InputDecoration(labelText: 'النص')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              if (title.text.trim().isEmpty || body.text.trim().isEmpty) return;
              await widget.repo.create(
                titleAr: title.text.trim(),
                bodyAr: body.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              final next = _load();
              setState(() {
                _rows = next;
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
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Icon(Icons.add)),
      body: FutureBuilder(
        future: _rows,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data!;
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(rows[i]['title_ar'] as String),
              subtitle: Text(rows[i]['body_ar'] as String),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () async {
                  await widget.repo.delete(rows[i]['id'] as int);
                  final next = _load();
                  setState(() {
                    _rows = next;
                  });
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
