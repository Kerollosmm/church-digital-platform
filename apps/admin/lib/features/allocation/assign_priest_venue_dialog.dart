import 'package:flutter/material.dart';
import '../bookings/event_booking_admin_models.dart';
import '../bookings/event_bookings_admin_repository.dart';

class AssignPriestVenueDialog extends StatefulWidget {
  const AssignPriestVenueDialog({
    super.key,
    required this.booking,
    required this.venues,
    required this.repository,
  });

  final EventBookingAdminItem booking;
  final List<VenueResourceItem> venues;
  final EventBookingsAdminRepository repository;

  @override
  State<AssignPriestVenueDialog> createState() =>
      _AssignPriestVenueDialogState();
}

class _AssignPriestVenueDialogState extends State<AssignPriestVenueDialog> {
  VenueResourceItem? _selectedVenue;
  PriestAdminItem? _selectedPriest;
  final _noteController = TextEditingController();
  bool _isLoadingPriests = true;
  bool _isSubmitting = false;
  String? _priestError;
  List<PriestAdminItem> _availablePriests = [];

  @override
  void initState() {
    super.initState();
    if (widget.venues.isNotEmpty) {
      _selectedVenue = widget.venues.firstWhere(
        (v) => v.id == widget.booking.assignedVenueId,
        orElse: () => widget.venues.first,
      );
    }
    _loadAvailablePriests();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailablePriests() async {
    setState(() {
      _isLoadingPriests = true;
      _priestError = null;
    });

    final res = await widget.repository.getAvailablePriests(
      startTime: widget.booking.startTime,
      endTime: widget.booking.endTime,
    );

    if (!mounted) return;
    res.fold(
      (fail) => setState(() {
        _priestError = fail.message;
        _isLoadingPriests = false;
      }),
      (priests) => setState(() {
        _availablePriests = priests;
        _isLoadingPriests = false;
        if (priests.isNotEmpty) {
          if (widget.booking.assignedPriestId != null) {
            _selectedPriest = priests.firstWhere(
              (p) => p.id == widget.booking.assignedPriestId,
              orElse: () => priests.first,
            );
          } else {
            _selectedPriest = priests.first;
          }
        }
      }),
    );
  }

  Future<void> _submitAssignment() async {
    if (_selectedVenue == null || _selectedPriest == null) return;
    setState(() => _isSubmitting = true);

    final res = await widget.repository.assignPriestAndVenue(
      bookingId: widget.booking.id,
      venueId: _selectedVenue!.id,
      priestId: _selectedPriest!.id,
      overrideNotes: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    res.fold(
      (fail) {
        String msg = 'فشل الإسناد: ${fail.message}';
        if (fail.message.contains('VENUE_ALREADY_BOOKED')) {
          msg = 'القاعة محجوزة بالفعل في هذا التوقيت';
        } else if (fail.message.contains('PRIEST_ALREADY_ASSIGNED')) {
          msg = 'الأب الكاهن غير متاح أو لديه التزام آخر في هذا التوقيت';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      },
      (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إسناد القاعة والأب الكاهن وتأكيد الحجز بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.assignment_ind, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'إسناد القاعة والأب الكاهن - ${widget.booking.eventTypeName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'صاحب الحجز: ${widget.booking.customerName ?? widget.booking.customerPhone ?? 'غير محدد'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'الموعد: ${widget.booking.startTime.toLocal().toString().substring(0, 16)} إلى ${widget.booking.endTime.toLocal().toString().substring(11, 16)}',
                      ),
                      const SizedBox(height: 4),
                      Text('الإجمالي: ${widget.booking.totalPriceEgp} ج.م'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'اختيار القاعة / المكان:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<VenueResourceItem>(
                initialValue: _selectedVenue,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.meeting_room),
                ),
                items: widget.venues
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(
                          '${v.nameAr} (${v.locationDetailsAr ?? ""})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedVenue = val),
              ),
              const SizedBox(height: 16),
              const Text(
                'الأب الكاهن المسؤول (المتاحون في هذا التوقيت):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_isLoadingPriests)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_priestError != null)
                Text(
                  'خطأ: $_priestError',
                  style: const TextStyle(color: Colors.red),
                )
              else if (_availablePriests.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.amber),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'لا يوجد كهنة متاحون في هذا التوقيت! جميع الآباء لديهم التزامات أخرى.',
                          style: TextStyle(color: Colors.brown),
                        ),
                      ),
                    ],
                  ),
                )
              else
                DropdownButtonFormField<PriestAdminItem>(
                  initialValue: _selectedPriest,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  items: _availablePriests
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            '${p.name} (${p.rank == "HEGUMEN" ? "قمص" : "قس"}${p.phone != null && p.phone!.isNotEmpty ? " - ${p.phone}" : ""})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setState(() => _selectedPriest = val),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات الإسناد والتأكيد (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed:
              (_isSubmitting ||
                  _selectedVenue == null ||
                  _selectedPriest == null)
              ? null
              : _submitAssignment,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('تأكيد وإسناد'),
        ),
      ],
    );
  }
}
