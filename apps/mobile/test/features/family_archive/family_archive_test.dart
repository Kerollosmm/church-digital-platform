import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/either.dart';
import 'package:mobile/core/failure.dart';
import 'package:mobile/features/family_archive/certificate_viewer_screen.dart';
import 'package:mobile/features/family_archive/family_certificates_screen.dart';
import 'package:mobile/features/family_archive/sacramental_models.dart';
import 'package:mobile/features/family_archive/sacramental_repository.dart';
import 'package:qr_flutter/qr_flutter.dart';

class FakeSacramentalRecordsRepository implements SacramentalRecordsRepository {
  List<SacramentalRecord> certificates = [
    SacramentalRecord(
      id: 'rec-1',
      sacramentType: SacramentType.baptism,
      recipientNameAr: 'كيرلس ميخائيل بطرس',
      recipientNationalId: '29901010101010',
      sacramentDate: DateTime(2026, 5, 15),
      officiatingPriestName: 'أبونا مرقس',
      churchLocationAr: 'كنيسة السيدة العذراء والأنبا بيشوي',
      registryBookNumber: '1',
      registryPageNumber: '42',
      registryEntryNumber: '105',
      godparentsAr: 'العراب مينا',
      verificationToken: 'token_hex_1234567890abcdef',
      status: 'ACTIVE',
      pdfStoragePath: 'certificates/1/user/cert.pdf',
      issuedAt: DateTime(2026, 5, 15, 10, 0),
    ),
    SacramentalRecord(
      id: 'rec-2',
      sacramentType: SacramentType.marriage,
      recipientNameAr: 'جورج فادي & مارينا سمير',
      sacramentDate: DateTime(2026, 6, 20),
      officiatingPriestName: 'أبونا أنطونيوس',
      churchLocationAr: 'كنيسة العذراء',
      verificationToken: 'token_marriage_abcdef123456',
      status: 'ACTIVE',
      issuedAt: DateTime(2026, 6, 20, 18, 0),
    ),
  ];

  bool shouldFail = false;

  @override
  Future<Either<Failure, List<SacramentalRecord>>> getMyCertificates() async {
    if (shouldFail) {
      return const Left(ServerFailure('فشل الاتصال بالخادم'));
    }
    return Right(certificates);
  }

  @override
  Future<Either<Failure, CertificateVerificationResult>> verifyCertificate(
    String token,
  ) async {
    if (token == 'valid_token_123') {
      return Right(
        CertificateVerificationResult(
          isValid: true,
          sacramentType: SacramentType.baptism,
          recipientNameAr: 'يوحنا سامي',
          sacramentDate: DateTime(2026, 3, 10),
          officiatingPriestName: 'أبونا ميخائيل',
          churchLocationAr: 'كنيسة السيدة العذراء والأنبا بيشوي',
          status: 'ACTIVE',
          issuedAt: DateTime(2026, 3, 10),
        ),
      );
    } else if (token == 'revoked_token_456') {
      return const Right(
        CertificateVerificationResult(
          isValid: false,
          isRevoked: true,
          status: 'REVOKED',
          revocationReason: 'إلغاء رسمي للشهادة',
          errorMessageAr: 'تم إلغاء هذه الشهادة رسمياً من قبل الكنيسة',
        ),
      );
    }
    return const Right(
      CertificateVerificationResult(
        isValid: false,
        errorMessageAr: 'الشهادة غير موجودة أو الرمز غير صحيح',
      ),
    );
  }

  @override
  Future<Either<Failure, String>> getCertificateSignedUrl(
    String pdfStoragePath,
  ) async {
    return const Right('https://storage.example.com/cert.pdf?token=signed');
  }
}

void main() {
  late FakeSacramentalRecordsRepository repo;

  setUp(() {
    repo = FakeSacramentalRecordsRepository();
  });

  test('SacramentalModels JSON serialization and type parsing', () {
    final record = SacramentalRecord.fromJson({
      'id': 'test-uuid',
      'sacrament_type': 'DEACON_ORDINATION',
      'recipient_name_ar': 'مينا إبراهيم',
      'sacrament_date': '2026-07-07',
      'officiating_priest_name': 'أبونا بولس',
      'verification_token': 'token123',
      'status': 'ACTIVE',
      'created_at': '2026-07-07T12:00:00Z',
    });

    expect(record.id, 'test-uuid');
    expect(record.sacramentType, SacramentType.deaconOrdination);
    expect(record.recipientNameAr, 'مينا إبراهيم');
    expect(record.isRevoked, false);
  });

  testWidgets('FamilyCertificatesScreen renders certificates list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: FamilyCertificatesScreen(repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('الأرشيف العائلي والشهادات الكنسية'), findsOneWidget);
    expect(find.text('كيرلس ميخائيل بطرس'), findsOneWidget);
    expect(find.text('جورج فادي & مارينا سمير'), findsOneWidget);
    expect(find.text('سر المعمودية'), findsOneWidget);
    expect(find.text('سر الزيجة / الإكليل'), findsOneWidget);
  });

  testWidgets(
    'CertificateViewerScreen renders digital certificate details and QR',
    (tester) async {
      final cert = repo.certificates.first;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: CertificateViewerScreen(record: cert, repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('كنيسة السيدة العذراء والأنبا بيشوي'), findsNWidgets(2));
      expect(find.text('شهادة سر المعمودية'), findsOneWidget);
      expect(find.text('كيرلس ميخائيل بطرس'), findsOneWidget);
      expect(find.text('أبونا مرقس'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('token_hex_1234567890abcdef'), findsOneWidget);
      expect(find.text('تحميل PDF'), findsOneWidget);
    },
  );

  testWidgets(
    'Verification BottomSheet validates token and displays verified record',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: FamilyCertificatesScreen(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open verification dialog
      await tester.tap(find.byIcon(Icons.qr_code_scanner));
      await tester.pumpAndSettle();

      expect(find.text('التحقق من صحة شهادة كنسية'), findsOneWidget);

      // Enter valid token
      await tester.enterText(
        find.widgetWithText(TextField, 'رمز التحقق (Hex Token)'),
        'valid_token_123',
      );

      // Tap verify
      await tester.tap(find.text('تحقق من السجل الكنسي'));
      await tester.pumpAndSettle();

      expect(find.text('شهادة رسمية موثقة وصحيحة'), findsOneWidget);
      expect(find.text('صاحب الشهادة: يوحنا سامي'), findsOneWidget);
      expect(find.text('الكاهن المتمم: أبونا ميخائيل'), findsOneWidget);
    },
  );
}
