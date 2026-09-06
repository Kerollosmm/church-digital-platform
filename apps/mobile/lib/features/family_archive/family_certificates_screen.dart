import 'package:flutter/material.dart';
import 'certificate_verification_sheet.dart';
import 'certificate_viewer_screen.dart';
import 'sacramental_models.dart';
import 'sacramental_repository.dart';

class FamilyCertificatesScreen extends StatefulWidget {
  const FamilyCertificatesScreen({super.key, required this.repository});

  final SacramentalRecordsRepository repository;

  @override
  State<FamilyCertificatesScreen> createState() =>
      _FamilyCertificatesScreenState();
}

class _FamilyCertificatesScreenState extends State<FamilyCertificatesScreen> {
  List<SacramentalRecord> _certificates = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCertificates();
  }

  Future<void> _loadCertificates() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await widget.repository.getMyCertificates();

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      res.fold(
        (failure) => _errorMessage = failure.message,
        (list) => _certificates = list,
      );
    });
  }

  void _openVerificationDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CertificateVerificationSheet(repository: widget.repository),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأرشيف العائلي والشهادات الكنسية'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'تحقق من شهادة',
            onPressed: _openVerificationDialog,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCertificates,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _ErrorView(
                    errorMessage: _errorMessage!,
                    onRetry: _loadCertificates,
                  )
                : _certificates.isEmpty
                    ? _EmptyCertificatesView(
                        onVerifyExternal: _openVerificationDialog,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _certificates.length,
                        itemBuilder: (context, index) {
                          final cert = _certificates[index];
                          return _CertificateCard(
                            certificate: cert,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (ctx) => CertificateViewerScreen(
                                    record: cert,
                                    repository: widget.repository,
                                  ),
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.errorMessage,
    required this.onRetry,
  });

  final String errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 12),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCertificatesView extends StatelessWidget {
  const _EmptyCertificatesView({
    required this.onVerifyExternal,
  });

  final VoidCallback onVerifyExternal;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.workspace_premium_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'لا توجد شهادات مسجلة بحسابك حالياً',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'تظهر هنا الشهادات الكنسية الموثقة (المعمودية، الإكليل، الرسامة، التناول) الصادرة من الكنيسة لك ولأفراد أسرتك.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onVerifyExternal,
              icon: const Icon(Icons.verified),
              label: const Text('التحقق من رمز شهادة خارجية'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CertificateCard extends StatelessWidget {
  const _CertificateCard({
    required this.certificate,
    required this.onTap,
  });

  final SacramentalRecord certificate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: certificate.isRevoked
              ? Colors.red.shade200
              : const Color(0xFFD4AF37),
          width: 1.2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFFAF0E6),
                    child: Icon(
                      certificate.sacramentType == SacramentType.marriage
                          ? Icons.favorite
                          : Icons.workspace_premium,
                      color: const Color(0xFF800020),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          certificate.sacramentType.labelAr,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          certificate.recipientNameAr,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: certificate.isRevoked
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      certificate.isRevoked ? 'ملغاة' : 'موثقة',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: certificate.isRevoked
                            ? Colors.red.shade900
                            : Colors.green.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${certificate.sacramentDate.year}-${certificate.sacramentDate.month.toString().padLeft(2, '0')}-${certificate.sacramentDate.day.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  const Row(
                    children: [
                      Text(
                        'عرض الشهادة ورمز QR',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        Icons.chevron_left,
                        size: 18,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
