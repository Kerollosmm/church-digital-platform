import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'events_provider.dart';
import 'event_booking_screen.dart';

class EventCatalogScreen extends ConsumerWidget {
  const EventCatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventTypesAsync = ref.watch(eventTypesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('حجز المناسبات والخدمات الكنسية'),
      ),
      body: eventTypesAsync.when(
        data: (eventTypes) {
          if (eventTypes.isEmpty) {
            return const Center(child: Text('لا توجد مناسبات متاحة حالياً'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: eventTypes.length,
            itemBuilder: (context, index) {
              final type = eventTypes[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(
                    type.nameAr,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  subtitle: Text(
                    type.descriptionAr ?? 'السعر الأساسي: ${type.basePriceEgp.toStringAsFixed(0)} ج.م',
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    ref.read(eventBookingNotifierProvider.notifier).selectEventType(type);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const EventBookingScreen(),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('حدث خطأ: $err')),
      ),
    );
  }
}
