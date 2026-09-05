import 'package:flutter/material.dart';
import 'sacramental_models.dart';
import 'sacramental_repository.dart';

class CertificateVerificationSheet extends StatefulWidget {
  const CertificateVerificationSheet({super.key, required this.repository});

  final SacramentalRecordsRepository repository;

  @override
  State<CertificateVerificationSheet> createState() =>
      _CertificateVerificationSheetState();
}

class _CertificateVerificationSheetState
    extends State<CertificateVerificationSheet> {
  final _tokenController = TextEditingController();
  CertificateVerificationResult? _verificationResult;
  bool _isVerifying = false;
  String? _verifyError;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.qr_code_scanner,
                  color: Color(0xFF800020),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'التحقق من صحة شهادة كنسية',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 20),
            const Text(
              'أدخل رمز التحقق المطبوع على الشهادة للتأكد من صحتها في السجل الرسمي للكنيسة:',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'رمز التحقق (Hex Token)',
                hintText: 'مثال: a1b2c3d4e5f6...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.verified_user_outlined),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isVerifying
                  ? null
                  : () async {
                      final token = _tokenController.text.trim();
                      if (token.isEmpty) return;

                      setState(() {
                        _isVerifying = true;
                        _verifyError = null;
                        _verificationResult = null;
                      });

                      final res = await widget.repository
                          .verifyCertificate(token);

                      if (!mounted) return;

                      setState(() {
                        _isVerifying = false;
                        res.fold(
                          (f) => _verifyError = f.message,
                          (result) => _verificationResult = result,
                        );
                      });
                    },
              icon: _isVerifying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: const Text('تحقق من السجل الكنسي'),
            ),
            if (_verifyError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _verifyError!,
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            ],
            if (_verificationResult != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _verificationResult!.isValid
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _verificationResult!.isValid
                        ? Colors.green.shade300
                        : Colors.red.shade300,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _verificationResult!.isValid
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: _verificationResult!.isValid
                              ? Colors.green
                              : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _verificationResult!.isValid
                              ? 'شهادة رسمية موثقة وصحيحة'
                              : _verificationResult!.isRevoked
                              ? 'شهادة ملغاة رسمياً'
                              : 'شهادة غير مسجلة أو غير صالحة',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: _verificationResult!.isValid
                                ? Colors.green.shade900
                                : Colors.red.shade900,
                          ),
                        ),
                      ],
                    ),
                    if (_verificationResult!.isValid) ...[
                      const Divider(height: 16),
                      Text(
                        'نوع السر: ${_verificationResult!.sacramentType?.labelAr ?? "-"}',
                      ),
                      Text(
                        'صاحب الشهادة: ${_verificationResult!.recipientNameAr ?? "-"}',
                      ),
                      if (_verificationResult!.sacramentDate != null)
                        Text(
                          'تاريخ إتمام السر: ${_verificationResult!.sacramentDate!.year}-${_verificationResult!.sacramentDate!.month.toString().padLeft(2, '0')}-${_verificationResult!.sacramentDate!.day.toString().padLeft(2, '0')}',
                        ),
                      if (_verificationResult!.officiatingPriestName !=
                          null)
                        Text(
                          'الكاهن المتمم: ${_verificationResult!.officiatingPriestName!}',
                        ),
                      if (_verificationResult!.churchLocationAr != null)
                        Text(
                          'المكان: ${_verificationResult!.churchLocationAr!}',
                        ),
                    ],
                    if (_verificationResult!.errorMessageAr != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          _verificationResult!.errorMessageAr!,
                          style: TextStyle(color: Colors.red.shade900),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
