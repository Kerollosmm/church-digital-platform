import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/controllers/run_guarded.dart';
import 'package:mobile/core/auth/auth_gateway.dart';
import 'package:mobile/core/auth/phone_verify_gate.dart';
import 'package:mobile/features/booking/booking_ticket_screen.dart';
import 'package:mobile/models/booking_status.dart';
import 'package:mobile/models/resolved_booking_status.dart';
import 'package:mobile/repositories/booking_repository.dart';
import 'package:mobile/services/app_routes.dart';
import 'package:mobile/services/app_strings.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({
    super.key,
    required this.repository,
    this.gateway,
    this.isLoggedIn,
  });

  final BookingRepository repository;
  final AuthGateway? gateway;
  final bool Function()? isLoggedIn;

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  late Future<List<Map<String, dynamic>>> _rows;
  @override
  void initState() {
    super.initState();
    _rows = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async =>
      widget.repository.myBookings();

  Future<void> _retry(int bookingId) async {
    await runGuarded(
      () async {
        if (!mounted) return;
        context.pushNamed(AppRoutes.paymentRedirect, extra: bookingId);
      },
      onError: (message) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final gateway = widget.gateway ?? resolveAuthGateway(null);
    return PhoneVerifyGate(
      gateway: gateway,
      isLoggedIn: widget.isLoggedIn,
      onVerified: () {
        setState(() {
          _rows = _load();
        });
      },
      child: Scaffold(
        appBar: AppBar(title: const Text(AppStrings.myBookingsTitle)),
        body: FutureBuilder(
          future: _rows,
          builder: (context, snapshot) {
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final rows = snapshot.data!;
            if (rows.isEmpty)
              return const Center(child: Text(AppStrings.myBookingsEmpty));
            return ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final r = rows[i];
                return Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    title: Text('${AppStrings.bookingNumberPrefix}${r['id']}'),
                    subtitle: Builder(
                      builder: (context) {
                        final resolved = resolveBookingStatus(
                          BookingStatus.fromDb(r['status'] as String),
                        );
                        return Chip(
                          label: Text(
                            resolved.label,
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: resolved.color.withValues(
                            alpha: 0.15,
                          ),
                        );
                      },
                    ),
                    trailing: (r['status'] == 'PENDING_PAYMENT')
                        ? TextButton(
                            onPressed: () => _retry(r['id'] as int),
                            child: const Text(AppStrings.retryPayment),
                          )
                        : null,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BookingTicketScreen(
                            booking: r,
                            repository: widget.repository,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
