import 'package:flutter/material.dart';

class VideosAdminScreen extends StatefulWidget {
  const VideosAdminScreen({super.key, required this.db});
  final dynamic db;
  @override
  State<VideosAdminScreen> createState() => _VideosAdminScreenState();
}

class _VideosAdminScreenState extends State<VideosAdminScreen> {
  late Future<List<Map<String, dynamic>>> _rows;
  @override
  void initState() { super.initState(); _rows = _load(); }
  Future<List<Map<String, dynamic>>> _load() async =>
      ((await widget.db.from('videos').select().order('created_at', ascending: false)) as List)
          .map((r) => Map<String, dynamic>.from(r as Map)).toList();

  Future<void> _create() async {
    final title = TextEditingController();
    final url = TextEditingController();
    final price = TextEditingController(text: '0');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة فيديو'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان')),
          TextField(controller: url, decoration: const InputDecoration(labelText: 'رابط يوتيوب')),
          TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              await widget.db.from('videos').insert({
                'title_ar': title.text, 'yt_url': url.text,
                'event_date': DateTime.now().toUtc().toIso8601String(),
                'price': int.tryParse(price.text) ?? 0, 'privacy': 'UNLISTED',
              });
              if (ctx.mounted) Navigator.pop(ctx);
              final next = _load();
              setState(() {
                _rows = next;
              });
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الفيديوهات')),
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Text('إضافة فيديو')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _rows,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data!;
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(rows[i]['title_ar'] as String),
              subtitle: Text('${rows[i]['price']} جنيه — ${rows[i]['privacy']}'),
            ),
          );
        },
      ),
    );
  }
}
