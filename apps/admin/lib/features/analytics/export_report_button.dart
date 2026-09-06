import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/result.dart';
import 'analytics_repository.dart';
import 'web_download_stub.dart' if (dart.library.js_interop) 'web_download.dart';

class ExportReportButton extends StatefulWidget {
  const ExportReportButton({
    super.key,
    this.repository,
    this.onExport,
    this.label = 'تصدير التقرير (CSV)',
  });

  final AnalyticsRepository? repository;
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
      Either<Failure, String> result;
      if (widget.onExport != null) {
        try {
          await widget.onExport!();
          result = const Right('');
        } catch (_) {
          result = const Left(
            Failure(code: 'INTERNAL', message: 'فشل تصدير التقرير'),
          );
        }
      } else if (widget.repository != null) {
        result = await widget.repository!.exportPaymentsCsv();
      } else {
        result = const Left(
          Failure(code: 'INTERNAL', message: 'فشل تصدير التقرير'),
        );
      }

      result.fold(
        (f) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(f.message),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        (csv) {
          if (kIsWeb && csv.isNotEmpty) {
            downloadCsvOnWeb(csv, 'analytics.csv');
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تم تصدير التقرير بنجاح'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
      );
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
