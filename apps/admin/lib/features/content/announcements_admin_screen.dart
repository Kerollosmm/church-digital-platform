import 'package:flutter/material.dart';

class AnnouncementsAdminScreen extends StatefulWidget {
  const AnnouncementsAdminScreen({super.key, required this.db});
  final dynamic db;
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
      ((await widget.db.from('announcements').select()) as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();

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
              await widget.db.from('announcements').insert({
                'title_ar': title.text, 'body_ar': body.text,
                'published_at': DateTime.now().toUtc().toIso8601String(),
              });
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
                  await widget.db.from('announcements').delete().eq('id', rows[i]['id']);
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
