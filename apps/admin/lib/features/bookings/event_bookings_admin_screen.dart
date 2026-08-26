import 'package:flutter/material.dart';
import 'event_booking_admin_models.dart';
import 'event_bookings_admin_repository.dart';

class EventBookingsAdminScreen extends StatefulWidget {
  const EventBookingsAdminScreen({super.key, required this.repository});

  final EventBookingsAdminRepository repository;

  @override
  State<EventBookingsAdminScreen> createState() =>
      _EventBookingsAdminScreenState();
}

class _EventBookingsAdminScreenState extends State<EventBookingsAdminScreen> {
  String? _selectedStatus;
  bool _isLoading = true;
  String? _error;
  List<EventBookingAdminItem> _bookings = [];
  List<VenueResourceItem> _venues = [];

  final List<String> _statuses = [
    'SUBMITTED',
    'CONFIRMED',
    'PENDING_PAYMENT',
    'PAID',
    'REJECTED',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final bookingsRes = await widget.repository.fetchEventBookings(
      statusFilter: _selectedStatus,
    );
    final venuesRes = await widget.repository.fetchVenues();

    venuesRes.fold((f) {}, (v) => _venues = v);

    bookingsRes.fold(
      (fail) => setState(() {
        _error = fail.message;
        _isLoading = false;
      }),
      (list) => setState(() {
        _bookings = list;
        _error = null;
        _isLoading = false;
      }),
    );
  }

  Future<void> _showConfirmModal(EventBookingAdminItem booking) async {
    VenueResourceItem? selectedVenue = _venues.isNotEmpty
        ? _venues.first
        : null;
    final noteController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text('تأكيد حجز ${booking.eventTypeName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<VenueResourceItem>(
                initialValue: selectedVenue,
                decoration: const InputDecoration(
                  labelText: 'القاعة / المكان المخصص',
                ),
                items: _venues
                    .map(
                      (v) => DropdownMenuItem(value: v, child: Text(v.nameAr)),
                    )
                    .toList(),
                onChanged: (val) => setModalState(() => selectedVenue = val),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'ملاحظات الإدارة'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: selectedVenue == null
                  ? null
                  : () async {
                      Navigator.of(ctx).pop();
                      final res = await widget.repository.confirmBooking(
                        bookingId: booking.id,
                        venueId: selectedVenue!.id,
                        adminNote: noteController.text.trim().isEmpty
                            ? null
                            : noteController.text.trim(),
                      );
                      res.fold(
                        (f) => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('فشل التأكيد: ${f.message}')),
                        ),
                        (_) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم تأكيد الحجز بنجاح'),
                            ),
                          );
                          _loadData();
                        },
                      );
                    },
              child: const Text('تأكيد وتعيين'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRejectModal(EventBookingAdminItem booking) async {
    final reasonController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفض طلب الحجز'),
        content: TextField(
          controller: reasonController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'سبب الرفض (إلزامي)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.of(ctx).pop();
              final res = await widget.repository.rejectBooking(
                bookingId: booking.id,
                rejectionReason: reasonController.text.trim(),
              );
              res.fold(
                (f) => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('فشل الرفض: ${f.message}')),
                ),
                (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم رفض الحجز وتوثيق السبب')),
                  );
                  _loadData();
                },
              );
            },
            child: const Text(
              'تأكيد الرفض',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCashPaymentModal(EventBookingAdminItem booking) async {
    final amountController = TextEditingController(
      text: booking.remainingAmountEgp.toString(),
    );
    final noteController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تحصيل نقدية بالخزينة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('المتبقي للحجز: ${booking.remainingAmountEgp} ج.م'),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'المبلغ المحصل (ج.م)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'ملاحظة الخزينة / المحصل',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final egp = int.tryParse(amountController.text.trim());
              if (egp == null || egp <= 0) return;
              Navigator.of(ctx).pop();
              final res = await widget.repository.recordCashPayment(
                bookingId: booking.id,
                amountPiastres: egp * 100,
                collectorNote: noteController.text.trim().isEmpty
                    ? null
                    : noteController.text.trim(),
              );
              res.fold(
                (f) => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('فشل تسجيل الدفع: ${f.message}')),
                ),
                (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم تسجيل التحصيل وتحديث الرصيد'),
                    ),
                  );
                  _loadData();
                },
              );
            },
            child: const Text('تسجيل التحصيل'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة حجوزات المناسبات الخاصة')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('الكل'),
                    selected: _selectedStatus == null,
                    onSelected: (_) {
                      setState(() => _selectedStatus = null);
                      _loadData();
                    },
                  ),
                  const SizedBox(width: 8),
                  ..._statuses.map((st) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(st),
                        selected: _selectedStatus == st,
                        onSelected: (_) {
                          setState(() => _selectedStatus = st);
                          _loadData();
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : _bookings.isEmpty
                ? const Center(child: Text('لا توجد طلبات حجز مطابقة'))
                : ListView.builder(
                    itemCount: _bookings.length,
                    itemBuilder: (ctx, i) {
                      final b = _bookings[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    b.eventTypeName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Chip(
                                    label: Text(b.status),
                                    backgroundColor: b.status == 'CONFIRMED'
                                        ? Colors.green.shade100
                                        : b.status == 'PAID'
                                        ? Colors.blue.shade100
                                        : b.status == 'REJECTED'
                                        ? Colors.red.shade100
                                        : Colors.orange.shade100,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'المطالب: ${b.customerName ?? 'مستخدم'} (${b.customerPhone ?? ''})',
                              ),
                              Text(
                                'الموعد: ${b.startTime.toString().substring(0, 16)}',
                              ),
                              if (b.venueName != null)
                                Text('المكان: ${b.venueName}'),
                              Text(
                                'الإجمالي: ${b.totalPriceEgp} ج.م | المدفوع: ${b.paidAmountEgp} ج.م',
                              ),
                              if (b.notes != null) Text('ملاحظات: ${b.notes}'),
                              if (b.rejectionReason != null)
                                Text(
                                  'سبب الرفض: ${b.rejectionReason}',
                                  style: const TextStyle(color: Colors.red),
                                ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (b.status == 'SUBMITTED') ...[
                                    OutlinedButton(
                                      onPressed: () => _showRejectModal(b),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                      child: const Text('رفض'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () => _showConfirmModal(b),
                                      child: const Text('تأكيد وتعيين مكان'),
                                    ),
                                  ],
                                  if (b.status == 'CONFIRMED') ...[
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.payments),
                                      label: const Text('تحصيل نقدية'),
                                      onPressed: () => _showCashPaymentModal(b),
                                    ),
                                  ],
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
