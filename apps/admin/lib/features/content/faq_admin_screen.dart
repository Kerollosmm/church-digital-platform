import 'package:flutter/material.dart';
import 'package:admin/features/content/content_repository.dart';

class FaqAdminScreen extends StatefulWidget {
  const FaqAdminScreen({super.key, required this.repository});
  final ContentRepository repository;
  @override
  State<FaqAdminScreen> createState() => _FaqAdminScreenState();
}

class _FaqAdminScreenState extends State<FaqAdminScreen> {
  List<Map<String, dynamic>>? _rows;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await widget.repository.faq();
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

  Future<void> _add() async {
    final q = TextEditingController();
    final a = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة سؤال'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: q,
              decoration: const InputDecoration(labelText: 'السؤال'),
            ),
            TextField(
              controller: a,
              decoration: const InputDecoration(labelText: 'الإجابة'),
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
              final res = await widget.repository.createFaq({
                'question_ar': q.text,
                'answer_ar': a.text,
                'position': 999,
                'published': true,
                'tenant_id': 1,
              });
              if (ctx.mounted) Navigator.pop(ctx);
              res.fold(
                (f) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(f.message)),
                    );
                  }
                },
                (_) => _load(),
              );
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
                  title: Text(r['question_ar'] as String),
                  subtitle: Text(r['answer_ar'] as String),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () async {
                      final id = r['id'] as int;
                      final res = await widget.repository.deleteFaq(id);
                      res.fold(
                        (f) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(f.message)),
                            );
                          }
                        },
                        (_) {
                          if (mounted) {
                            setState(() {
                              _rows?.removeWhere((row) => row['id'] == id);
                            });
                          }
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
