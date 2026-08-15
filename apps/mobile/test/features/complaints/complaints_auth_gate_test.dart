import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_gateway.dart';
import 'package:mobile/core/auth/phone_verify_gate.dart';
import 'package:mobile/features/complaints/complaints_models.dart';
import 'package:mobile/features/complaints/complaints_repository.dart';
import 'package:mobile/features/complaints/complaints_screen.dart';
import 'package:mobile/services/app_strings.dart';
import '../../helpers/mock_auth_gateway.dart';


class MockComplaintsRepo implements ComplaintsRepository {
  @override
  Future<List<ComplaintItem>> myComplaints() async => [
    ComplaintItem(
      id: 201,
      category: 'عامة',
      status: 'NEW',
      createdAt: DateTime.now(),
    ),
  ];

  @override
  Future<int> submitComplaint({
    required String category,
    required String body,
  }) async => 202;
}

void main() {
  testWidgets(
    'ComplaintsScreen renders PhoneVerifyForm when unauthenticated and reveals complaint form on verify',
    (tester) async {
      final mockGateway = MockAuthGateway();
      final repo = MockComplaintsRepo();

      await tester.pumpWidget(
        MaterialApp(
          home: ComplaintsScreen(
            repository: repo,
            gateway: mockGateway,
            isLoggedIn: () => mockGateway.isAuthenticated,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Logged out -> PhoneVerifyForm shown
      expect(find.byType(PhoneVerifyForm), findsOneWidget);
      expect(find.text('تقديم شكوى أو اقتراح جديد'), findsNothing);

      // 2. Submit phone + OTP
      await tester.enterText(find.byType(TextFormField), '01033334444');
      await tester.tap(find.text(AppStrings.sendOtpCta));
      await tester.pumpAndSettle();

      final otpFields = find.byType(TextField);
      for (int i = 0; i < 6; i++) {
        await tester.enterText(otpFields.at(i), '${i + 1}');
      }
      await tester.pumpAndSettle();

      // 3. Authenticated -> Complaints form visible
      expect(mockGateway.isAuthenticated, isTrue);
      expect(find.text('تقديم شكوى أو اقتراح جديد'), findsOneWidget);
      expect(find.text('#201'), findsOneWidget);
    },
  );
}
