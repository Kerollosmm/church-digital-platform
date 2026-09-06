import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_colors.dart';
import 'sacramental_models.dart';
import 'sacramental_repository.dart';

class CertificateViewerScreen extends StatefulWidget {
  const CertificateViewerScreen({
    super.key,
    required this.record,
    required this.repository,
  });

  final SacramentalRecord record;
  final SacramentalRecordsRepository repository;

  @override
  State<CertificateViewerScreen> createState() =>
      _CertificateViewerScreenState();
}

class _CertificateViewerScreenState extends State<CertificateViewerScreen> {
  bool _isDownloading = false;

  Future<void> _downloadPdf() async {
    if (widget.record.pdfStoragePath == null ||
        widget.record.pdfStoragePath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ملف PDF غير متاح حالياً لهذه الشهادة')),
      );
      return;
    }

    setState(() => _isDownloading = true);

    final res = await widget.repository.getCertificateSignedUrl(
      widget.record.pdfStoragePath!,
    );

    if (!mounted) return;

    setState(() => _isDownloading = false);

    res.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تجهيز رابط التحميل: ${failure.message}')),
        );
      },
      (url) async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تعذر فتح رابط تحميل الشهادة')),
            );
          }
        }
      },
    );
  }

  void _copyToken() {
    Clipboard.setData(ClipboardData(text: widget.record.verificationToken));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم نسخ رمز التحقق الرقمي')));
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F6F0),
      appBar: AppBar(
        title: Text(record.sacramentType.labelAr),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'نسخ رمز التحقق',
            onPressed: _copyToken,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          children: [
            // Revocation Banner if revoked
            if (record.isRevoked)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: AppColors.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'تم إلغاء هذه الشهادة رسمياً',
                            style: TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (record.revocationReason != null)
                            Text(
                              'السبب: ${record.revocationReason}',
                              style: const TextStyle(
                                color: AppColors.onErrorContainer,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Certificate Visual Frame
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD4AF37), width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  // Church Header
                  const Icon(Icons.church, size: 40, color: Color(0xFF800020)),
                  const SizedBox(height: 8),
                  const Text(
                    'كنيسة السيدة العذراء والأنبا بيشوي',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF800020),
                    ),
                  ),
                  const Text(
                    'بطريركية الأقباط الأرثوذكس',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 1.5,
                    width: 140,
                    color: const Color(0xFFD4AF37),
                  ),
                  const SizedBox(height: 12),

                  // Sacrament Title
                  Text(
                    'شهادة ${record.sacramentType.labelAr}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Recipient Name
                  const Text(
                    'تشهد الكنيسة بأن المبارك / المباركة',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    record.recipientNameAr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF800020),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Details Grid
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF8F5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE8E0D5)),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow(
                          'تاريخ إتمام السر:',
                          '${record.sacramentDate.year}-${record.sacramentDate.month.toString().padLeft(2, '0')}-${record.sacramentDate.day.toString().padLeft(2, '0')}',
                        ),
                        if (record.officiatingPriestName != null)
                          _buildDetailRow(
                            'الكاهن المتمم للسر:',
                            record.officiatingPriestName!,
                          ),
                        _buildDetailRow('المكان:', record.churchLocationAr),
                        if (record.godparentsAr != null)
                          _buildDetailRow(
                            'العراب / الشهود:',
                            record.godparentsAr!,
                          ),
                        if (record.registryBookNumber != null ||
                            record.registryPageNumber != null ||
                            record.registryEntryNumber != null)
                          _buildDetailRow(
                            'القيد الكنسي:',
                            'دفتر: ${record.registryBookNumber ?? "-"} | ص: ${record.registryPageNumber ?? "-"} | قيد: ${record.registryEntryNumber ?? "-"}',
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Cryptographic QR Code
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
                        QrImageView(
                          data: record.verificationToken,
                          version: QrVersions.auto,
                          size: 150.0,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'رمز التحقق الكنسي الموثق (QR)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          record.verificationToken,
                          style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  Text(
                    'تاريخ الإصدار: ${record.issuedAt.year}-${record.issuedAt.month.toString().padLeft(2, '0')}-${record.issuedAt.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyToken,
                    icon: const Icon(Icons.copy),
                    label: const Text('نسخ الرمز'),
                  ),
                ),
                if (record.pdfStoragePath != null && !record.isRevoked) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isDownloading ? null : _downloadPdf,
                      icon: _isDownloading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download),
                      label: const Text('تحميل PDF'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}
