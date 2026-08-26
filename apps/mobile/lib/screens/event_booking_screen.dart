import 'package:flutter/material.dart';
import '../models/event_booking.dart';
import '../repositories/event_booking_repository.dart';

class EventBookingScreen extends StatefulWidget {
  const EventBookingScreen({super.key, required this.repository});

  final EventBookingRepository repository;

  @override
  State<EventBookingScreen> createState() => _EventBookingScreenState();
}

class _EventBookingScreenState extends State<EventBookingScreen> {
  bool _isLoading = true;
  String? _error;
  List<EventType> _eventTypes = [];
  EventType? _selectedEventType;
  List<ExtraService> _availableExtras = [];
  final Map<String, int> _selectedQuantities = {};
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 3));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 18, minute: 0);
  final _notesController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadEventTypes();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadEventTypes() async {
    setState(() => _isLoading = true);
    final res = await widget.repository.fetchEventTypes();
    if (!mounted) return;
    res.fold(
      (fail) => setState(() {
        _error = fail.message;
        _isLoading = false;
      }),
      (types) {
        setState(() {
          _eventTypes = types;
          _isLoading = false;
          if (types.isNotEmpty) {
            _onEventTypeSelected(types.first);
          }
        });
      },
    );
  }

  Future<void> _onEventTypeSelected(EventType type) async {
    setState(() {
      _selectedEventType = type;
      _availableExtras = [];
      _selectedQuantities.clear();
    });
    final res = await widget.repository.fetchExtraServicesForEvent(type.id);
    if (!mounted) return;
    // Guard against out-of-order responses overwriting newer selections
    if (_selectedEventType?.id != type.id) return;
    res.fold((fail) {}, (extras) => setState(() => _availableExtras = extras));
  }

  int get _calculatedTotalPiastres {
    if (_selectedEventType == null) return 0;
    int total = _selectedEventType!.basePricePiastres;
    for (final extra in _availableExtras) {
      final qty = _selectedQuantities[extra.id] ?? 0;
      total += extra.pricePiastres * qty;
    }
    return total;
  }

  double get _calculatedTotalEgp => _calculatedTotalPiastres / 100.0;

  Future<void> _submit() async {
    if (_selectedEventType == null) return;
    setState(() => _isSubmitting = true);

    final startDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final extraList = <Map<String, dynamic>>[];
    _selectedQuantities.forEach((id, qty) {
      if (qty > 0) {
        extraList.add({'extra_service_id': id, 'quantity': qty});
      }
    });

    final res = await widget.repository.submitEventBooking(
      eventTypeId: _selectedEventType!.id,
      startTime: startDateTime,
      extraServices: extraList,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    res.fold(
      (fail) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشل الحجز: ${fail.message}')));
      },
      (bookingId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تقديم طلب الحجز بنجاح!')),
        );
        Navigator.of(context).pop(bookingId);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حجز مناسبة خاصة')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'نوع المناسبة',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<EventType>(
                    initialValue: _selectedEventType,
                    items: _eventTypes.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(
                          '${type.nameAr} (${type.basePriceEgp.toStringAsFixed(type.basePriceEgp.truncateToDouble() == type.basePriceEgp ? 0 : 2)} ج.م)',
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        _onEventTypeSelected(val);
                      }
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_availableExtras.isNotEmpty) ...[
                    const Text(
                      'الخدمات الإضافية',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._availableExtras.map((extra) {
                      final currentQty = _selectedQuantities[extra.id] ?? 0;
                      return CheckboxListTile(
                        title: Text(extra.nameAr),
                        subtitle: Text(
                          '${extra.priceEgp.toStringAsFixed(extra.priceEgp.truncateToDouble() == extra.priceEgp ? 0 : 2)} ج.م',
                        ),
                        value: currentQty > 0,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedQuantities[extra.id] = 1;
                            } else {
                              _selectedQuantities.remove(extra.id);
                            }
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 16),
                  ],
                  const Text(
                    'الموعد المقترح',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                            '${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}',
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime.now().add(
                                const Duration(days: 1),
                              ),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked != null) {
                              setState(() => _selectedDate = picked);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.access_time),
                          label: Text(_selectedTime.format(context)),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: _selectedTime,
                            );
                            if (picked != null) {
                              setState(() => _selectedTime = picked);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات إضافية',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'الإجمالي التقديري:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_calculatedTotalEgp.toStringAsFixed(_calculatedTotalEgp.truncateToDouble() == _calculatedTotalEgp ? 0 : 2)} ج.م',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSubmitting
                        ? const CircularProgressIndicator()
                        : const Text(
                            'تأكيد طلب الحجز',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
