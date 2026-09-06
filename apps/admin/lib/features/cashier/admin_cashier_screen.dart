import 'package:flutter/material.dart';
import '../bookings/event_booking_admin_models.dart';
import '../bookings/event_bookings_admin_repository.dart';

class AdminCashierScreen extends StatefulWidget {
  const AdminCashierScreen({super.key, required this.repository});

  final EventBookingsAdminRepository repository;

  @override
  State<AdminCashierScreen> createState() => _AdminCashierScreenState();
}

class _AdminCashierScreenState extends State<AdminCashierScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  String? _error;
  List<EventBookingAdminItem> _allBookings = [];
  String? _selectedCategory; // null = All, 'SACRAMENT', 'ACTIVITY'

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBookings() async {
    setState(() => _isLoading = true);
    final query = _searchController.text.trim();
    final res = await widget.repository.searchCashierBookings(
      categoryFilter: _selectedCategory,
      searchQuery: query.isNotEmpty ? query : null,
    );
    res.fold(
      (fail) => setState(() {
        _error = fail.message;
        _isLoading = false;
      }),
      (list) => setState(() {
        _allBookings = list;
        _error = null;
        _isLoading = false;
      }),
    );
  }

  List<EventBookingAdminItem> get _filteredBookings {
    final query = _searchController.text.trim().toLowerCase();
    return _allBookings.where((b) {
      if (_selectedCategory != null && b.category != _selectedCategory) {
        return false;
      }
      if (query.isEmpty) return true;
      final phone = b.customerPhone?.toLowerCase() ?? '';
      final name = b.customerName?.toLowerCase() ?? '';
      final eventName = b.eventTypeName.toLowerCase();
      final id = b.id.toLowerCase();
      return phone.contains(query) ||
          name.contains(query) ||
          eventName.contains(query) ||
          id.contains(query);
    }).toList();
  }

  Future<void> _showQuickCashModal(EventBookingAdminItem booking) async {
    final remaining = booking.remainingAmountEgp;
    final amountController = TextEditingController(
      text: remaining > 0 ? remaining.toStringAsFixed(0) : '0',
    );
    final noteController = TextEditingController(text: 'تحصيل نقدي بالخزينة');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.point_of_sale, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'تحصيل سريع: ${booking.eventTypeName}',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('صاحب الحجز: ${booking.customerName ?? 'غير محدد'}'),
                    Text('رقم الهاتف: ${booking.customerPhone ?? 'غير متوفر'}'),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('الإجمالي المستحق:'),
                        Text(
                          '${booking.totalPriceEgp} ج.م',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('المسدد سابقاً:'),
                        Text(
                          '${booking.paidAmountEgp} ج.م',
                          style: const TextStyle(color: Colors.blue),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('المتبقي للتحصيل:'),
                        Text(
                          '$remaining ج.م',
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'المبلغ المحصل الآن (ج.م)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة الإيصال / الخزينة',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.receipt_long),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: const Icon(Icons.check_circle),
            label: const Text('تأكيد التحصيل وإصدار إشعار'),
            onPressed: () async {
              final egp = int.tryParse(amountController.text.trim());
              if (egp == null || egp <= 0) return;
              Navigator.of(ctx).pop();
              final res = await widget.repository.quickCashCollect(
                bookingId: booking.id,
                amountPiastres: egp * 100,
                collectorNote: noteController.text.trim().isEmpty
                    ? null
                    : noteController.text.trim(),
              );
              res.fold(
                (f) => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('فشل التحصيل: ${f.message}')),
                ),
                (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم تحصيل النقدية وتحديث الحجز بنجاح 🎉'),
                    ),
                  );
                  _loadBookings();
                },
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredBookings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('خزينة التحصيل الكنسي المباشر 💵'),
        actions: [
          IconButton(
            tooltip: 'تحديث البيانات',
            icon: const Icon(Icons.refresh),
            onPressed: _loadBookings,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter header
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.grey.shade50,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText:
                              'بحث فوري برقم التليفون، اسم المخدوم، أو نوع المناسبة...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    _loadBookings();
                                  },
                                )
                              : null,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) => _loadBookings(),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('جميع المعاملات'),
                        selected: _selectedCategory == null,
                        onSelected: (_) {
                          setState(() => _selectedCategory = null);
                          _loadBookings();
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('✝️ أسرار ومناسبات كنسية'),
                        selected: _selectedCategory == 'SACRAMENT',
                        onSelected: (_) {
                          setState(() => _selectedCategory = 'SACRAMENT');
                          _loadBookings();
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('🚌 رحلات ومؤتمرات'),
                        selected: _selectedCategory == 'ACTIVITY',
                        onSelected: (_) {
                          setState(() => _selectedCategory = 'ACTIVITY');
                          _loadBookings();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Booking List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : filtered.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد حجوزات مطابقة لمعايير البحث في الخزينة',
                      style: TextStyle(fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, idx) {
                      final item = filtered[idx];
                      final isPending = item.remainingAmountEgp > 0;
                      final totalStr = item.totalPriceEgp.toStringAsFixed(item.totalPriceEgp.truncateToDouble() == item.totalPriceEgp ? 0 : 2);
                      final remainingStr = item.remainingAmountEgp.toStringAsFixed(item.remainingAmountEgp.truncateToDouble() == item.remainingAmountEgp ? 0 : 2);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isPending
                                ? Colors.orange.shade300
                                : Colors.green.shade300,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: item.isSacrament
                                      ? Colors.blue.shade50
                                      : Colors.amber.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  item.isSacrament
                                      ? Icons.church
                                      : Icons.directions_bus,
                                  color: item.isSacrament
                                      ? Colors.blue.shade800
                                      : Colors.amber.shade900,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          item.eventTypeName,
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            item.category,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'المخدوم: ${item.customerName ?? 'مستخدم'} | الهاتف: ${item.customerPhone ?? 'غير متوفر'}',
                                      style: TextStyle(
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                    Text(
                                      'الموعد: ${item.startTime.toString().substring(0, 16)}',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'الإجمالي: $totalStr ج.م',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    'المتبقي: $remainingStr ج.م',
                                    style: TextStyle(
                                      color: isPending
                                          ? Colors.red.shade700
                                          : Colors.green.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isPending
                                          ? Colors.green.shade700
                                          : Colors.grey.shade400,
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(
                                      Icons.point_of_sale,
                                      size: 16,
                                    ),
                                    label: const Text('تحصيل نقدية'),
                                    onPressed: isPending
                                        ? () => _showQuickCashModal(item)
                                        : null,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

        ],
      ),
    );
  }
}
