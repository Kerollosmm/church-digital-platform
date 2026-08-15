import 'package:flutter/material.dart';
import '../controllers/dashboard_controller.dart';
import '../models/booking.dart';
import '../models/booking_status.dart';
import '../models/resolved_booking_status.dart';
import '../repositories/booking_repository.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.repository});
  final BookingRepository repository;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardController _controller;
  late Future<List<Booking>> _future;
  @override
  void initState() {
    super.initState();
    _controller = DashboardController(widget.repository);
    _future = _controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الرئيسية')),
      body: FutureBuilder<List<Booking>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final bookings = snapshot.data!;
          if (bookings.isEmpty) return const Text('لا توجد حجوزات');
          return ListView.builder(
            itemCount: bookings.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(bookings[i].serviceName),
              subtitle: Text(
                resolveBookingStatus(
                  BookingStatus.fromDb(bookings[i].status),
                ).label,
              ),
            ),
          );
        },
      ),
    );
  }
}
