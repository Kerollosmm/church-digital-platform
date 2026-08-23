import 'package:flutter/material.dart';
import 'package:admin/features/content/content_repository.dart';
import 'package:admin/core/result.dart';

class FaqAdminScreen extends StatefulWidget {
  const FaqAdminScreen({super.key, required this.repository});
  final ContentRepository repository;
  @override
  State<FaqAdminScreen> createState() => _FaqAdminScreenState();
}

class _FaqAdminScreenState extends State<FaqAdminScreen> {
  late Future<List<Map<String, dynamic>>> _rows;
  @override
  void initState() {
    super.initState();
    _rows = widget.repository.faq().then(unwrapOrThrow);
  }

  Future<void> _add() async {
    final q = TextEditingController();
    final a = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة سؤال'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: q, decoration: const InputDecoration(labelText: 'السؤال')),
          TextField(controller: a, decoration: const InputDecoration(labelText: 'الإجابة')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              (await widget.repository.createFaq({
                'question_ar': q.text,
                'answer_ar': a.text,
                'position': 999,
                'published': true,
                'tenant_id': 1,
              })).fold((f) => throw f, (_) => {});
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() {
                _rows = widget.repository.faq().then(unwrapOrThrow);
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
      appBar: AppBar(title: const Text('الأسئلة الشائعة')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Text('إضافة سؤال'),
      ),
      body: FutureBuilder(
        future: _rows,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (_, i) {
              final r = snapshot.data![i];
              return ListTile(
                title: Text(r['question_ar'] as String),
                subtitle: Text(r['answer_ar'] as String),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    (await widget.repository.deleteFaq(r['id'] as int)).fold((f) => throw f, (_) => {});
                    if (mounted) {
                      setState(() {
                        _rows = widget.repository.faq().then(unwrapOrThrow);
                      });
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
