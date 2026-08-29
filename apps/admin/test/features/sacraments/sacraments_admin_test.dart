import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/core/result.dart';
import 'package:admin/features/sacraments/sacramental_models.dart';
import 'package:admin/features/sacraments/sacramental_registrar_screen.dart';
import 'package:admin/features/sacraments/sacraments_admin_repository.dart';
import 'package:admin/features/sacraments/issue_sacrament_dialog.dart';
import 'package:admin/features/sacraments/sacrament_details_dialog.dart';

class FakeSacramentsAdminRepository implements SacramentsAdminRepository {
  final List<SacramentalRecord> records = [
    SacramentalRecord(
      id: 'rec-1',
      sacramentType: SacramentType.baptism,
      recipientNameAr: 'كيرلس ميخائيل بطرس',
      recipientNationalId: '29901010101010',
      sacramentDate: DateTime(2026, 5, 15),
      officiatingPriestId: 1,
      officiatingPriestName: 'أبونا مرقس',
      churchLocationAr: 'كنيسة السيدة العذراء والأنبا بيشوي',
      registryBookNumber: '1',
      registryPageNumber: '42',
      registryEntryNumber: '105',
      godparentsAr: 'العراب مينا',
      verificationToken: 'token_hex_1234567890abcdef',
      status: 'ACTIVE',
      createdAt: DateTime(2026, 5, 15, 10, 0),
      createdBy: 'admin-uuid',
    ),
    SacramentalRecord(
      id: 'rec-2',
      sacramentType: SacramentType.marriage,
      recipientNameAr: 'جورج فادي & مارينا سمير',
      recipientNationalId: '29502020202020',
      sacramentDate: DateTime(2026, 6, 20),
      officiatingPriestId: 2,
      officiatingPriestName: 'أبونا أنطونيوس',
      churchLocationAr: 'كنيسة العذراء',
      verificationToken: 'token_marriage_abcdef123456',
      status: 'ACTIVE',
      createdAt: DateTime(2026, 6, 20, 18, 0),
      createdBy: 'admin-uuid',
    ),
  ];

  final List<Map<String, dynamic>> priests = [
    {'id': 1, 'name': 'أبونا مرقس', 'rank': 'HEGUMEN'},
    {'id': 2, 'name': 'أبونا أنطونيوس', 'rank': 'PRIEST'},
  ];

  @override
  Future<Either<Failure, List<SacramentalRecord>>> fetchSacramentalRecords({
    String? sacramentTypeFilter,
    String? searchQuery,
  }) async {
    var list = List<SacramentalRecord>.from(records);
    if (sacramentTypeFilter != null &&
        sacramentTypeFilter.isNotEmpty &&
        sacramentTypeFilter != 'ALL') {
      list = list
          .where((r) => r.sacramentType.value == sacramentTypeFilter)
          .toList();
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      list = list
          .where((r) => r.recipientNameAr.contains(searchQuery))
          .toList();
    }
    return Right(list);
  }

  @override
  Future<Either<Failure, SacramentalRecord>> issueSacramentalCertificate(
    IssueSacramentInput input,
  ) async {
    final newRec = SacramentalRecord(
      id: 'rec-${records.length + 1}',
      sacramentType: input.sacramentType,
      recipientNameAr: input.recipientNameAr,
      recipientNationalId: input.recipientNationalId,
      recipientUserId: input.recipientUserId,
      sacramentDate: input.sacramentDate,
      officiatingPriestId: input.officiatingPriestId,
      officiatingPriestName: priests.firstWhere(
        (p) => p['id'] == input.officiatingPriestId,
        orElse: () => {'name': 'كاهن الكنيسة'},
      )['name'],
      churchLocationAr: input.churchLocationAr,
      registryBookNumber: input.registryBookNumber,
      registryPageNumber: input.registryPageNumber,
      registryEntryNumber: input.registryEntryNumber,
      godparentsAr: input.godparentsAr,
      verificationToken: 'token_new_${records.length + 1}',
      status: 'ACTIVE',
      pdfStoragePath: input.pdfStoragePath,
      notes: input.notes,
      createdAt: DateTime.now(),
      createdBy: 'admin-uuid',
    );
    records.insert(0, newRec);
    return Right(newRec);
  }

  @override
  Future<Either<Failure, void>> revokeCertificate({
    required String recordId,
    required String reason,
  }) async {
    final idx = records.indexWhere((r) => r.id == recordId);
    if (idx != -1) {
      final old = records[idx];
      records[idx] = SacramentalRecord(
        id: old.id,
        sacramentType: old.sacramentType,
        recipientNameAr: old.recipientNameAr,
        recipientNationalId: old.recipientNationalId,
        recipientUserId: old.recipientUserId,
        sacramentDate: old.sacramentDate,
        officiatingPriestId: old.officiatingPriestId,
        officiatingPriestName: old.officiatingPriestName,
        churchLocationAr: old.churchLocationAr,
        registryBookNumber: old.registryBookNumber,
        registryPageNumber: old.registryPageNumber,
        registryEntryNumber: old.registryEntryNumber,
        godparentsAr: old.godparentsAr,
        verificationToken: old.verificationToken,
        status: 'REVOKED',
        revocationReason: reason,
        pdfStoragePath: old.pdfStoragePath,
        notes: old.notes,
        createdAt: old.createdAt,
        createdBy: old.createdBy,
      );
      return const Right(null);
    }
    return const Left(Failure(code: 'NOT_FOUND', message: 'Record not found'));
  }

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> fetchPriests() async =>
      Right(priests);
}

void main() {
  late FakeSacramentsAdminRepository repo;

  setUp(() {
    repo = FakeSacramentsAdminRepository();
  });

  testWidgets(
    'SacramentalRegistrarScreen renders records table and filter options',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: SacramentalRegistrarScreen(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('سجلات الأسرار والشهادات الكنسية'), findsOneWidget);
      expect(find.text('كيرلس ميخائيل بطرس'), findsOneWidget);
      expect(find.text('جورج فادي & مارينا سمير'), findsOneWidget);
      expect(find.text('سر المعمودية'), findsOneWidget);
      expect(find.text('سر الزيجة / الإكليل'), findsOneWidget);
      expect(find.text('إصدار شهادة جديدة'), findsOneWidget);
    },
  );

  testWidgets('SacramentalRegistrarScreen filters by sacrament type', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: SacramentalRegistrarScreen(repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Select Marriage filter
    await tester.tap(find.text('جميع الأسرار'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('سر الزيجة').last);
    await tester.pumpAndSettle();

    expect(find.text('جورج فادي & مارينا سمير'), findsOneWidget);
    expect(find.text('كيرلس ميخائيل بطرس'), findsNothing);
  });

  testWidgets(
    'SacramentDetailsDialog displays record canonical metadata and token',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final record = repo.records.first;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: SacramentDetailsDialog(record: record)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('تفاصيل سر المعمودية'), findsOneWidget);
      expect(find.text('كيرلس ميخائيل بطرس'), findsNWidgets(2));
      expect(find.text('29901010101010'), findsOneWidget);
      expect(find.text('أبونا مرقس'), findsOneWidget);
      expect(find.text('token_hex_1234567890abcdef'), findsOneWidget);
      expect(find.text('سارية وموثقة'), findsOneWidget);
    },
  );

  testWidgets('IssueSacramentDialog validates and submits new certificate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: IssueSacramentDialog(repository: repo)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('إصدار شهادة سر كنسي جديدة'), findsOneWidget);

    // Fill form
    await tester.enterText(
      find.widgetWithText(TextFormField, 'اسم صاحب السر باللغة العربية *'),
      'يوسف صموئيل بشارة',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'الرقم القومي (اختياري)'),
      '29803030303030',
    );

    // Submit
    await tester.tap(find.text('إصدار وحفظ الشهادة'));
    await tester.pumpAndSettle();

    expect(repo.records.length, 3);
    expect(repo.records.first.recipientNameAr, 'يوسف صموئيل بشارة');
  });

  testWidgets('Revocation dialog updates certificate status to revoked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: SacramentalRegistrarScreen(repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Ensure revoke button is visible in horizontal scroll and tap it
    final revokeBtn = find.byIcon(Icons.block).first;
    await tester.ensureVisible(revokeBtn);
    await tester.pumpAndSettle();
    await tester.tap(revokeBtn);
    await tester.pumpAndSettle();

    expect(find.text('إلغاء سر المعمودية'), findsOneWidget);

    // Fill revocation reason
    await tester.enterText(
      find.widgetWithText(TextFormField, 'سبب الإلغاء الرسمي *'),
      'خطأ كتابي في بيانات المعمودية',
    );

    // Confirm revocation
    await tester.tap(find.text('تأكيد الإلغاء'));
    await tester.pumpAndSettle();

    expect(repo.records.first.status, 'REVOKED');
    expect(
      repo.records.first.revocationReason,
      'خطأ كتابي في بيانات المعمودية',
    );
  });
}
