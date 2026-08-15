import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'attendance_chart_widget.dart';
import 'export_report_button.dart';
import 'revenue_chart_widget.dart';

class AnalyticsAdminScreen extends StatelessWidget {
  const AnalyticsAdminScreen({super.key, this.client});

  final SupabaseClient? client;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة التحليلات'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ExportReportButton(client: client),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AttendanceChartWidget(client: client),
            const SizedBox(height: 16),
            RevenueChartWidget(client: client),
          ],
        ),
      ),
    );
  }
}
