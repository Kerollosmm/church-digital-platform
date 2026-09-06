import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'analytics_repository.dart';
import 'export_report_button.dart';

typedef RevenueQueryFetcher = Future<List<Map<String, dynamic>>> Function();

class RevenueChartWidget extends StatefulWidget {
  const RevenueChartWidget({
    super.key,
    this.repo,
    this.client,
    this.fetchData,
    this.initialData,
  });

  final AnalyticsRepository? repo;
  // Retained solely for the export edge-function invocation.
  final SupabaseClient? client;
  final RevenueQueryFetcher? fetchData;
  final List<Map<String, dynamic>>? initialData;

  @override
  State<RevenueChartWidget> createState() => _RevenueChartWidgetState();
}

class _RevenueChartWidgetState extends State<RevenueChartWidget> {
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _data = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _data = widget.initialData!;
      _loading = false;
    } else if (widget.fetchData != null || widget.repo != null) {
      _loadData();
    } else {
      _loading = false;
    }
  }

  Future<void> _loadData() async {
    try {
      final List<Map<String, dynamic>> rows;
      if (widget.fetchData != null) {
        rows = await widget.fetchData!();
      } else if (widget.repo != null) {
        rows = (await widget.repo!.paymentRows()).fold(
          (f) => throw f,
          (r) => r,
        );
      } else {
        rows = [];
      }
      if (mounted) {
        setState(() {
          _data = rows;
          _loading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('RevenueChart fetch error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = 'حدث خطأ أثناء تحميل البيانات';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Card(
        margin: const EdgeInsets.all(16.0),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'توزيع الإيرادات والمدفوعات',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ExportReportButton(
                    repository: widget.repo ??
                        (widget.client == null
                            ? null
                            : AnalyticsRepository(widget.client!)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildLegend(),
              const SizedBox(height: 16),
              if (_loading)
                const SizedBox(
                  height: 250,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                SizedBox(
                  height: 250,
                  child: Center(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                )
              else if (_data.isEmpty || _hasNoRevenueData())
                const SizedBox(
                  height: 250,
                  child: Center(child: Text('لا توجد بيانات متاحة')),
                )
              else
                SizedBox(height: 280, child: PieChart(_buildChartData())),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasNoRevenueData() {
    double total = 0;
    for (final item in _data) {
      total += _numVal(item['total_paid'] ?? item['paid']);
      total += _numVal(item['total_refunded'] ?? item['refunded']);
    }
    return total <= 0;
  }

  double _numVal(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 24,
      runSpacing: 8,
      children: [
        _legendItem('مدفوع', Colors.teal),
        _legendItem('مسترد', Colors.redAccent),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  PieChartData _buildChartData() {
    double totalPaid = 0;
    double totalRefunded = 0;

    for (final item in _data) {
      totalPaid += _numVal(item['total_paid'] ?? item['paid']);
      totalRefunded += _numVal(item['total_refunded'] ?? item['refunded']);
    }

    final double grandTotal = totalPaid + totalRefunded;

    final sections = <PieChartSectionData>[];

    if (totalPaid > 0) {
      final pct = (totalPaid / grandTotal * 100).toStringAsFixed(1);
      sections.add(
        PieChartSectionData(
          color: Colors.teal,
          value: totalPaid,
          title: '$pct%',
          radius: 55,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    }

    if (totalRefunded > 0) {
      final pct = (totalRefunded / grandTotal * 100).toStringAsFixed(1);
      sections.add(
        PieChartSectionData(
          color: Colors.redAccent,
          value: totalRefunded,
          title: '$pct%',
          radius: 55,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    }

    return PieChartData(
      sections: sections,
      centerSpaceRadius: 40,
      sectionsSpace: 3,
      pieTouchData: PieTouchData(enabled: true),
    );
  }
}
