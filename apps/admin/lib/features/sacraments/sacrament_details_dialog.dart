import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'sacramental_models.dart';

class SacramentDetailsDialog extends StatelessWidget {
  const SacramentDetailsDialog({super.key, required this.record});

  final SacramentalRecord record;

  static void show(BuildContext context, SacramentalRecord record) {
    showDialog(
      context: context,
      builder: (ctx) => SacramentDetailsDialog(record: record),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    record.isRevoked ? Icons.cancel : Icons.verified,
                    color: record.isRevoked ? Colors.red : Colors.green,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تفاصيل ${record.sacramentType.labelAr}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          record.recipientNameAr,
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
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: record.isRevoked
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: record.isRevoked ? Colors.red : Colors.green,
                      ),
                    ),
                    child: Text(
                      record.isRevoked ? 'ملغاة' : 'سارية وموثقة',
                      style: TextStyle(
                        color: record.isRevoked
                            ? Colors.red.shade900
                            : Colors.green.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (record.isRevoked && record.revocationReason != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'سبب الإلغاء: ${record.revocationReason}',
                                  style: TextStyle(
                                    color: Colors.red.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      _buildInfoTile(
                        'اسم صاحب السر',
                        record.recipientNameAr,
                        Icons.person,
                      ),
                      if (record.recipientNationalId != null)
                        _buildInfoTile(
                          'الرقم القومي',
                          record.recipientNationalId!,
                          Icons.badge,
                        ),
                      _buildInfoTile(
                        'تاريخ إتمام السر',
                        '${record.sacramentDate.year}-${record.sacramentDate.month.toString().padLeft(2, '0')}-${record.sacramentDate.day.toString().padLeft(2, '0')}',
                        Icons.calendar_today,
                      ),
                      if (record.officiatingPriestName != null)
                        _buildInfoTile(
                          'الكاهن المتمم للسر',
                          record.officiatingPriestName!,
                          Icons.person_pin,
                        ),
                      _buildInfoTile(
                        'مكان إتمام السر',
                        record.churchLocationAr,
                        Icons.church,
                      ),
                      if (record.godparentsAr != null)
                        _buildInfoTile(
                          'العراب / الإشبين / الشهود',
                          record.godparentsAr!,
                          Icons.people,
                        ),
                      if (record.registryBookNumber != null ||
                          record.registryPageNumber != null ||
                          record.registryEntryNumber != null)
                        _buildInfoTile(
                          'بيانات القيد الكنسي',
                          'دفتر: ${record.registryBookNumber ?? "-"} | صفحة: ${record.registryPageNumber ?? "-"} | قيد: ${record.registryEntryNumber ?? "-"}',
                          Icons.menu_book,
                        ),
                      _buildTokenTile(context, record.verificationToken),
                      if (record.pdfStoragePath != null)
                        _buildInfoTile(
                          'مسار ملف PDF',
                          record.pdfStoragePath!,
                          Icons.picture_as_pdf,
                        ),
                      if (record.notes != null)
                        _buildInfoTile(
                          'ملاحظات إدارية',
                          record.notes!,
                          Icons.note,
                        ),
                      _buildInfoTile(
                        'تاريخ الإصدار والتوثيق',
                        record.createdAt.toLocal().toString().split('.').first,
                        Icons.access_time,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إغلاق'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.blueGrey),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.black54)),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenTile(BuildContext context, String token) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.qr_code, size: 20, color: Colors.blueGrey),
          const SizedBox(width: 12),
          const SizedBox(
            width: 140,
            child: Text(
              'رمز التحقق الرقمي',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    token,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'نسخ الرمز',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: token));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم نسخ رمز التحقق')),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
