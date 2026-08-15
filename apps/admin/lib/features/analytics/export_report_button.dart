import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'web_download_stub.dart' if (dart.library.html) 'web_download.dart';

class ExportReportButton extends StatefulWidget {
  const ExportReportButton({
    super.key,
    this.client,
    this.onExport,
    this.label = 'تصدير التقرير (CSV)',
  });

  final dynamic client;
  final Future<void> Function()? onExport;
  final String label;

  @override
  State<ExportReportButton> createState() => _ExportReportButtonState();
}

class _ExportReportButtonState extends State<ExportReportButton> {
  bool _loading = false;

  Future<void> _handleExport() async {
    setState(() {
      _loading = true;
    });

    try {
      if (widget.onExport != null) {
        await widget.onExport!();
      } else if (widget.client != null) {
        final res = await widget.client!.functions.invoke(
          'analytics-export',
          method: HttpMethod.get,
          queryParameters: const {'report': 'payments'},
        );
        if (res.status != 200) {
          throw Exception('Failed with status ${res.status}');
        }
        final csvData = res.data?.toString() ?? '';
        if (kIsWeb && csvData.isNotEmpty) {
          downloadCsvOnWeb(csvData, 'analytics.csv');
        }
      } else {
        throw Exception('No client or export handler provided');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تصدير التقرير بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Export failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تصدير التقرير: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _handleExport,
        icon: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download),
        label: Text(widget.label),
      ),
    );
  }
}
