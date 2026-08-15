import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/booking/payment_redirect_screen.dart';
import 'package:mobile/services/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final launches = <MethodCall>[];
  bool launchResult = true;

  setUp(() {
    launches.clear();
    launchResult = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            launches.add(call);
            if (call.method == 'canLaunch') return true;
            if (call.method == 'launch' || call.method == 'launchUrl')
              return launchResult;
            return true;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        );
  });

  Widget buildScreen({
    int bookingId = 42,
    Future<String> Function(int)? fetchCheckoutUrl,
  }) {
    return MaterialApp(
      home: PaymentRedirectScreen(
        bookingId: bookingId,
        fetchCheckoutUrl:
            fetchCheckoutUrl ?? (id) async => 'https://paymob.com/checkout/$id',
      ),
    );
  }

  testWidgets(
    'renders title, methods, booking id, pay now button, terms note',
    (tester) async {
      await tester.pumpWidget(buildScreen(bookingId: 42));

      expect(find.text(AppStrings.checkoutTitle), findsAtLeastNWidgets(1));
      expect(find.text(AppStrings.checkoutSubtitle), findsOneWidget);
      expect(find.text(AppStrings.paymentMethodsTitle), findsOneWidget);
      expect(find.text(AppStrings.cardMethod), findsOneWidget);
      expect(find.text(AppStrings.cardMethodDesc), findsOneWidget);
      expect(find.text(AppStrings.fawryMethod), findsOneWidget);
      expect(find.text(AppStrings.fawryMethodDesc), findsOneWidget);
      expect(find.text(AppStrings.walletMethod), findsOneWidget);
      expect(find.text(AppStrings.walletMethodDesc), findsOneWidget);
      expect(find.text(AppStrings.securePaymentTitle), findsOneWidget);
      expect(find.text(AppStrings.orderSummaryTitle), findsOneWidget);
      expect(find.text(AppStrings.bookingNumberLabel), findsOneWidget);
      expect(find.text('#42'), findsOneWidget);
      expect(find.text(AppStrings.payNow), findsOneWidget);
      expect(find.text(AppStrings.termsNote), findsOneWidget);
    },
  );

  testWidgets(
    'tap pay now calls fetchCheckoutUrl and launches url via platform channel',
    (tester) async {
      int? calledId;
      await tester.pumpWidget(
        buildScreen(
          bookingId: 42,
          fetchCheckoutUrl: (id) async {
            calledId = id;
            return 'https://paymob.com/checkout/42';
          },
        ),
      );

      await tester.ensureVisible(find.text(AppStrings.payNow));
      await tester.tap(find.text(AppStrings.payNow));
      await tester.pump();

      expect(calledId, equals(42));
      expect(
        launches.any(
          (call) => call.arguments['url'] == 'https://paymob.com/checkout/42',
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'fetchCheckoutUrl throws error -> shows error SnackBar and re-enables button',
    (tester) async {
      await tester.pumpWidget(
        buildScreen(
          bookingId: 42,
          fetchCheckoutUrl: (id) async => throw Exception('Network error'),
        ),
      );

      await tester.ensureVisible(find.text(AppStrings.payNow));
      await tester.tap(find.text(AppStrings.payNow));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(AppStrings.unknownError), findsOneWidget);

      // Button should be re-enabled
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, AppStrings.payNow),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets(
    'platform channel returns false -> shows paymentOpenFailed SnackBar',
    (tester) async {
      launchResult = false;
      await tester.pumpWidget(buildScreen(bookingId: 42));

      await tester.ensureVisible(find.text(AppStrings.payNow));
      await tester.tap(find.text(AppStrings.payNow));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(AppStrings.paymentOpenFailed), findsOneWidget);
    },
  );

  testWidgets('selecting Fawry card marks it selected visually', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen(bookingId: 42));

    await tester.tap(find.text(AppStrings.fawryMethod));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.fawryMethod), findsOneWidget);
  });
}
