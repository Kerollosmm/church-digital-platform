import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'bookings_provider.dart';

class BookingsAdminScreen extends ConsumerWidget {
  const BookingsAdminScreen({super.key, required this.gateway});
  final BookingsGateway gateway;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bookingsProvider(gateway));
    final notifier = ref.read(bookingsProvider(gateway).notifier);
    final filter = ref.watch(bookingsFilterProvider);

    const statuses = [
      'PENDING_PAYMENT',
      'AWAITING_CALL',
      'CONFIRMED',
      'COMPLETED',
      'CANCELLED',
      'RESCHEDULED',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('الحجوزات')),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                FilterChip(
                  label: const Text('الكل'),
                  selected: filter == null,
                  onSelected: (_) {
                    ref.read(bookingsFilterProvider.notifier).setFilter(null);
                  },
                ),
                for (final s in statuses)
                  FilterChip(
                    label: Text(s),
                    selected: filter == s,
                    onSelected: (_) {
                      ref.read(bookingsFilterProvider.notifier).setFilter(s);
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                if (state.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = state.bookings;
                if (rows.isEmpty) return const Text('لا توجد حجوزات');
                return ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return ListTile(
                      title: Text('حجز #${r['id']} — ${r['status']}'),
                      subtitle: Text('${r['paid_amount']} جنيه'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (r['status'] == 'AWAITING_CALL')
                            IconButton(
                              icon: const Icon(Icons.check_circle),
                              onPressed: () =>
                                  notifier.confirmBooking(r['id'] as int),
                            ),
                          if (r['status'] == 'CONFIRMED')
                            IconButton(
                              icon: const Icon(Icons.done_all),
                              onPressed: () =>
                                  notifier.completeBooking(r['id'] as int),
                            ),
                          if (r['status'] == 'PENDING_PAYMENT' ||
                              r['status'] == 'AWAITING_CALL')
                            IconButton(
                              icon: const Icon(Icons.cancel),
                              onPressed: () =>
                                  notifier.cancelBooking(r['id'] as int),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
