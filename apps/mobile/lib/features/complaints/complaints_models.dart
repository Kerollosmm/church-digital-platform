class ComplaintItem {
  final int id;
  final String category;
  final String status;
  final String? assignedTo;
  final DateTime? createdAt;

  const ComplaintItem({
    required this.id,
    required this.category,
    required this.status,
    this.assignedTo,
    this.createdAt,
  });

  factory ComplaintItem.fromJson(Map<String, dynamic> json) => ComplaintItem(
    id: json['id'] as int? ?? 0,
    category: json['category'] as String? ?? '',
    status: json['status'] as String? ?? 'NEW',
    assignedTo: json['assigned_to'] as String?,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
  );

  String get statusLabel {
    switch (status) {
      case 'IN_PROGRESS':
        return 'قيد المتابعة';
      case 'RESOLVED':
        return 'تم الحل';
      case 'NEW':
      default:
        return 'جديد';
    }
  }
}
