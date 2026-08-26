import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'analytics_repository.dart';

typedef AttendanceQueryFetcher = Future<List<Map<String, dynamic>>> Function();

class AttendanceChartWidget extends StatefulWidget {
  const AttendanceChartWidget({
    super.key,
    this.repo,
    this.client,
    this.fetchData,
    this.initialData,
  });

  final AnalyticsRepository? repo;
  // Retained solely for the export edge-function invocation.
  final SupabaseClient? client;
  final AttendanceQueryFetcher? fetchData;
  final List<Map<String, dynamic>>? initialData;

  @override
  State<AttendanceChartWidget> createState() => _AttendanceChartWidgetState();
}

class _AttendanceChartWidgetState extends State<AttendanceChartWidget> {
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
        rows = (await widget.repo!.utilizationRows()).fold(
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
      debugPrint('AttendanceChart fetch error: $e');
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
              Text(
                'نسبة الحضور والإشغال للمواظبين والحجوزات',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
              else if (_data.isEmpty)
                const SizedBox(
                  height: 250,
                  child: Center(child: Text('لا توجد بيانات متاحة')),
                )
              else
                SizedBox(height: 280, child: BarChart(_buildChartData())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      children: [
        _legendItem('السعة الكلية', Colors.blue.shade300),
        const SizedBox(width: 24),
        _legendItem('الحضور الفعلي', Colors.teal),
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

  BarChartData _buildChartData() {
    final barGroups = <BarChartGroupData>[];
    double maxY = 10;

    for (int i = 0; i < _data.length; i++) {
      final item = _data[i];
      final capacity = ((item['slots_total'] ?? item['capacity'] ?? 100) as num)
          .toDouble();
      final booked =
          ((item['slots_booked'] ??
                      item['attendees'] ??
                      item['actual_attendees'] ??
                      0)
                  as num)
              .toDouble();

      if (capacity > maxY) maxY = capacity;
      if (booked > maxY) maxY = booked;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: capacity,
              color: Colors.blue.shade300,
              width: 14,
              borderRadius: BorderRadius.circular(4),
            ),
            BarChartRodData(
              toY: booked,
              color: Colors.teal,
              width: 14,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: maxY * 1.15,
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final title = _getServiceTitle(groupIndex);
            final typeLabel = rodIndex == 0 ? 'السعة الكلية' : 'الحضور الفعلي';
            return BarTooltipItem(
              '$title\n$typeLabel: ${rod.toY.toInt()}',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            );
          },
        ),
      ),
      titlesData: FlTitlesData(
        show: true,
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            getTitlesWidget: (value, meta) {
              return Text(
                value.toInt().toString(),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= _data.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Text(
                  _getServiceTitle(index),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY > 50 ? (maxY / 5).clamp(10, 100) : 10,
        getDrawingHorizontalLine: (value) =>
            FlLine(color: Colors.grey.shade200, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      barGroups: barGroups,
    );
  }

  String _getServiceTitle(int index) {
    if (index < 0 || index >= _data.length) return '';
    final item = _data[index];
    return (item['title_ar'] ?? item['service_name'] ?? item['title'] ?? 'قداس')
        .toString();
  }
}
