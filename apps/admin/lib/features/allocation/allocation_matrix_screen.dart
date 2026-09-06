import 'package:flutter/material.dart';
import '../bookings/event_booking_admin_models.dart';
import '../bookings/event_bookings_admin_repository.dart';
import 'assign_priest_venue_dialog.dart';

class AllocationMatrixCalendarScreen extends StatefulWidget {
  const AllocationMatrixCalendarScreen({super.key, required this.repository});

  final EventBookingsAdminRepository repository;

  @override
  State<AllocationMatrixCalendarScreen> createState() =>
      _AllocationMatrixCalendarScreenState();
}

class _AllocationMatrixCalendarScreenState
    extends State<AllocationMatrixCalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  String? _error;

  List<EventBookingAdminItem> _allBookings = [];
  List<VenueResourceItem> _venues = [];
  List<PriestAdminItem> _priests = [];

  String? _selectedVenueFilter;
  int? _selectedPriestFilter;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final bookingsRes = await widget.repository.fetchEventBookings();
    final venuesRes = await widget.repository.fetchVenues();
    final priestsRes = await widget.repository.fetchPriests();

    if (!mounted) return;

    venuesRes.fold((f) {}, (v) => _venues = v);
    priestsRes.fold((f) {}, (p) => _priests = p);

    bookingsRes.fold(
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

  List<EventBookingAdminItem> get _unassignedBookings {
    return _allBookings.where((b) {
      return b.status == 'SUBMITTED' ||
          (b.assignedVenueId == null || b.assignedPriestId == null);
    }).toList();
  }

  List<EventBookingAdminItem> get _dayBookings {
    return _allBookings.where((b) {
      final isSameDay =
          b.startTime.year == _selectedDate.year &&
          b.startTime.month == _selectedDate.month &&
          b.startTime.day == _selectedDate.day;
      if (!isSameDay) return false;
      if (_selectedVenueFilter != null &&
          b.assignedVenueId != _selectedVenueFilter) {
        return false;
      }
      if (_selectedPriestFilter != null &&
          b.assignedPriestId != _selectedPriestFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _openAssignDialog(EventBookingAdminItem booking) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AssignPriestVenueDialog(
        booking: booking,
        venues: _venues,
        repository: widget.repository,
      ),
    );
    if (updated == true) {
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مصفوفة تخصيص القاعات والآباء الكهنة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث البيانات',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('خطأ: $_error'))
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left/Main Area: Visual Matrix and Filters
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AllocationControlsCard(
                          selectedDate: _selectedDate,
                          onDateChanged: (val) =>
                              setState(() => _selectedDate = val),
                          selectedVenueFilter: _selectedVenueFilter,
                          venues: _venues,
                          onVenueFilterChanged: (val) =>
                              setState(() => _selectedVenueFilter = val),
                          selectedPriestFilter: _selectedPriestFilter,
                          priests: _priests,
                          onPriestFilterChanged: (val) =>
                              setState(() => _selectedPriestFilter = val),
                        ),
                        const SizedBox(height: 16),
                        // Matrix Calendar View
                        Expanded(
                          child: _venues.isEmpty
                              ? const Center(child: Text('لا توجد قاعات مضافة'))
                              : _buildAllocationGrid(),
                        ),
                      ],
                    ),
                  ),
                ),
                // Right Sidebar: Unassigned Bookings Queue
                Expanded(
                  flex: 1,
                  child: _UnassignedBookingsPanel(
                    unassignedBookings: _unassignedBookings,
                    onAssign: _openAssignDialog,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAllocationGrid() {
    final activeVenues = _venues.where((v) {
      if (_selectedVenueFilter != null && v.id != _selectedVenueFilter) {
        return false;
      }
      return true;
    }).toList();

    return Card(
      elevation: 2,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: activeVenues.length,
        separatorBuilder: (context, index) => const Divider(height: 32),
        itemBuilder: (ctx, idx) {
          final venue = activeVenues[idx];
          final venueBookings = _dayBookings
              .where((b) => b.assignedVenueId == venue.id)
              .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.meeting_room, color: Colors.indigo),
                  const SizedBox(width: 8),
                  Text(
                    venue.nameAr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  if (venue.locationDetailsAr != null &&
                      venue.locationDetailsAr!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '(${venue.locationDetailsAr})',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '${venueBookings.length} حجوزات اليوم',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (venueBookings.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: const Text(
                    'القاعة متاحة طوال اليوم - لا توجد حجوزات مسندة',
                    style: TextStyle(color: Colors.green),
                  ),
                )
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: venueBookings.map((b) {
                    return InkWell(
                      onTap: () => _openAssignDialog(b),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 260,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _statusColor(b.status).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _statusColor(
                              b.status,
                            ).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    b.eventTypeName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _statusColor(b.status),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _statusLabelAr(b.status),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Colors.black54,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${b.startTime.toLocal().toString().substring(11, 16)} - ${b.endTime.toLocal().toString().substring(11, 16)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.person_pin,
                                  size: 14,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'الأب الكاهن: ${b.priestName ?? "غير محدد"}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'الحاجز: ${b.customerName ?? b.customerPhone ?? "غير محدد"}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          );
        },
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'CONFIRMED':
      return Colors.blue;
    case 'PENDING_PAYMENT':
      return Colors.amber.shade700;
    case 'PAID':
      return Colors.green;
    case 'SUBMITTED':
      return Colors.orange;
    case 'REJECTED':
    case 'CANCELLED':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

String _statusLabelAr(String status) {
  switch (status) {
    case 'SUBMITTED':
      return 'قيد الانتظار';
    case 'CONFIRMED':
      return 'مؤكد ومسند';
    case 'PENDING_PAYMENT':
      return 'بانتظار الدفع';
    case 'PAID':
      return 'مدفوع';
    case 'REJECTED':
      return 'مرفوض';
    case 'CANCELLED':
      return 'ملغي';
    default:
      return status;
  }
}

class _AllocationControlsCard extends StatelessWidget {
  const _AllocationControlsCard({
    required this.selectedDate,
    required this.onDateChanged,
    required this.selectedVenueFilter,
    required this.venues,
    required this.onVenueFilterChanged,
    required this.selectedPriestFilter,
    required this.priests,
    required this.onPriestFilterChanged,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final String? selectedVenueFilter;
  final List<VenueResourceItem> venues;
  final ValueChanged<String?> onVenueFilterChanged;
  final int? selectedPriestFilter;
  final List<PriestAdminItem> priests;
  final ValueChanged<int?> onPriestFilterChanged;

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 12.0,
        ),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            // Date Navigator
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    onDateChanged(
                      selectedDate.subtract(
                        const Duration(days: 1),
                      ),
                    );
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      onDateChanged(picked);
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    onDateChanged(
                      selectedDate.add(
                        const Duration(days: 1),
                      ),
                    );
                  },
                ),
                ElevatedButton(
                  onPressed: () => onDateChanged(DateTime.now()),
                  child: const Text('اليوم'),
                ),
              ],
            ),
            // Venue Filter
            DropdownButton<String?>(
              value: selectedVenueFilter,
              hint: const Text('كل القاعات'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('كل القاعات'),
                ),
                ...venues.map(
                  (v) => DropdownMenuItem(
                    value: v.id,
                    child: Text(v.nameAr),
                  ),
                ),
              ],
              onChanged: onVenueFilterChanged,
            ),
            // Priest Filter
            DropdownButton<int?>(
              value: selectedPriestFilter,
              hint: const Text('كل الكهنة'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('كل الكهنة'),
                ),
                ...priests.map(
                  (p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name),
                  ),
                ),
              ],
              onChanged: onPriestFilterChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _UnassignedBookingsPanel extends StatelessWidget {
  const _UnassignedBookingsPanel({
    required this.unassignedBookings,
    required this.onAssign,
  });

  final List<EventBookingAdminItem> unassignedBookings;
  final ValueChanged<EventBookingAdminItem> onAssign;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          right: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                const Icon(
                  Icons.pending_actions,
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                Text(
                  'طلبات بانتظار التخصيص (${unassignedBookings.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: unassignedBookings.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد طلبات جديدة معلقة',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: unassignedBookings.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final item = unassignedBookings[i];
                      return Card(
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    item.eventTypeName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _statusColor(
                                        item.status,
                                      ).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _statusLabelAr(item.status),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: _statusColor(item.status),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'صاحب الحجز: ${item.customerName ?? item.customerPhone ?? "غير محدد"}',
                                style: const TextStyle(
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                'الموعد: ${item.startTime.toLocal().toString().substring(0, 16)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: const Icon(
                                    Icons.assignment_ind,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'إسناد وتأكيد',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    visualDensity:
                                        VisualDensity.compact,
                                  ),
                                  onPressed: () => onAssign(item),
                                ),
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
