import 'package:flutter/material.dart';
import 'complaints_admin_repository.dart';

class ComplaintsAdminScreen extends StatefulWidget {
  const ComplaintsAdminScreen({super.key, required this.repo});
  final ComplaintsAdminRepository repo;

  @override
  State<ComplaintsAdminScreen> createState() => _ComplaintsAdminScreenState();
}

class _ComplaintsAdminScreenState extends State<ComplaintsAdminScreen> {
  ComplaintsAdminRepository get _repo => widget.repo;

  List<Map<String, dynamic>> _allComplaints = [];
  String? _selectedStatus;
  String? _selectedCategory;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadComplaints();
  }

  Future<void> _loadComplaints() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await _repo.list();
      final list = res.fold((f) => throw f, (rows) => rows);
      if (mounted) {
        setState(() {
          _allComplaints = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _decryptComplaint(int complaintId) async {
    try {
      final outcome = await _repo.decrypt(complaintId);
      final decryptedText = outcome.fold((f) => throw f, (t) => t);
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text('محتوى الشكوى #$complaintId'),
              content: SelectableText(
                decryptedText.isEmpty ? 'لا يوجد نص' : decryptedText,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Complaint decryption failure: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل فك التشفير. يرجى المحاولة لاحقاً.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _allComplaints
        .map((c) => c['category']?.toString())
        .whereType<String>()
        .toSet()
        .toList();

    final filteredComplaints = _allComplaints.where((c) {
      if (_selectedStatus != null && c['status'] != _selectedStatus) {
        return false;
      }
      if (_selectedCategory != null && c['category'] != _selectedCategory) {
        return false;
      }
      return true;
    }).toList();

    const statuses = ['NEW', 'ASSIGNED', 'RESOLVED'];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة الشكاوى'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadComplaints,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text('خطأ: $_error'))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: _selectedStatus == null
                                  ? Colors.blue.withValues(alpha: 0.1)
                                  : null,
                            ),
                            onPressed: () =>
                                setState(() => _selectedStatus = null),
                            child: const Text('الكل'),
                          ),
                          const SizedBox(width: 8),
                          for (final status in statuses) ...[
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: _selectedStatus == status
                                    ? Colors.blue.withValues(alpha: 0.1)
                                    : null,
                              ),
                              onPressed: () =>
                                  setState(() => _selectedStatus = status),
                              child: Text('حالة: '),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (categories.isNotEmpty) ...[
                            const VerticalDivider(width: 16),
                            DropdownButton<String?>(
                              value: _selectedCategory,
                              hint: const Text('تصفية حسب الفئة'),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('كل الفئات'),
                                ),
                                ...categories.map(
                                  (cat) => DropdownMenuItem<String?>(
                                    value: cat,
                                    child: Text('تصنيف: '),
                                  ),
                                ),
                              ],
                              onChanged: (val) =>
                                  setState(() => _selectedCategory = val),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: filteredComplaints.isEmpty
                        ? const Center(child: Text('لا توجد شكاوى'))
                        : ListView.builder(
                            itemCount: filteredComplaints.length,
                            itemBuilder: (context, index) {
                              final item = filteredComplaints[index];
                              final id = item['id'] as int;
                              final status = item['status'] as String? ?? 'NEW';
                              final category =
                                  item['category'] as String? ?? '';
                              final assignedTo = item['assigned_to']
                                  ?.toString();
                              final createdAt =
                                  item['created_at']?.toString() ?? '';

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                child: ListTile(
                                  title: Row(
                                    children: [
                                      Text('شكوى #$id'),
                                      const SizedBox(width: 12),
                                      Chip(
                                        label: Text(
                                          status,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white,
                                          ),
                                        ),
                                        backgroundColor: status == 'NEW'
                                            ? Colors.blue
                                            : status == 'ASSIGNED'
                                            ? Colors.orange
                                            : Colors.green,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text('الفئة: $category'),
                                      if (assignedTo != null)
                                        Text('مسندة إلى: $assignedTo'),
                                      Text('تاريخ الإنشاء: $createdAt'),
                                    ],
                                  ),
                                  trailing: ElevatedButton.icon(
                                    icon: const Icon(Icons.lock_open, size: 16),
                                    label: const Text('فك التشفير'),
                                    onPressed: () => _decryptComplaint(id),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
