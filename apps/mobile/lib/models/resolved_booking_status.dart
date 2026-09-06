import 'package:flutter/material.dart';
import 'booking_status.dart';

class ResolvedBookingStatus {
  const ResolvedBookingStatus({
    required this.label,
    required this.color,
    required this.sortWeight,
  });
  final String label;
  final MaterialColor color;
  final int sortWeight;
}

ResolvedBookingStatus resolveBookingStatus(BookingStatus status) =>
    switch (status) {
      BookingStatus.pendingPayment => const ResolvedBookingStatus(
        label: 'في انتظار الدفع',
        color: Colors.amber,
        sortWeight: 2,
      ),
      BookingStatus.awaitingCall => const ResolvedBookingStatus(
        label: 'بانتظار الاتصال',
        color: Colors.amber,
        sortWeight: 3,
      ),
      BookingStatus.confirmed => const ResolvedBookingStatus(
        label: 'مؤكد',
        color: Colors.green,
        sortWeight: 4,
      ),
      BookingStatus.completed => const ResolvedBookingStatus(
        label: 'مكتمل',
        color: Colors.grey,
        sortWeight: 5,
      ),
      BookingStatus.cancelled => const ResolvedBookingStatus(
        label: 'ملغي',
        color: Colors.red,
        sortWeight: 0,
      ),
      BookingStatus.rescheduled => const ResolvedBookingStatus(
        label: 'أعيدت جدولته',
        color: Colors.blue,
        sortWeight: 1,
      ),
    };
