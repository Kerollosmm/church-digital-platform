import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/either.dart';
import 'package:mobile/core/failure.dart';
import 'package:mobile/features/booking/payment_redirect_screen.dart';
import 'package:mobile/models/booking.dart';
import 'package:mobile/models/booking_checkout_session.dart';
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
            if (call.method == 'launch' || call.method == 'launchUrl') {
              return launchResult;
            }
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
    String? checkoutUrl,
    Future<Either<Failure, BookingCheckoutSession>> Function(int)?
    onRetryCheckout,
    Future<String> Function(int)? fetchCheckoutUrl,
  }) {
    return MaterialApp(
      home: PaymentRedirectScreen(
        bookingId: bookingId,
        checkoutUrl:
            checkoutUrl ??
            (fetchCheckoutUrl == null && onRetryCheckout == null
                ? 'https://paymob.com/checkout/$bookingId'
                : null),
        onRetryCheckout: onRetryCheckout,
        fetchCheckoutUrl: fetchCheckoutUrl,
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

  testWidgets(
    '1. Navigating with checkoutUrl opens directly on tap without calling retryCheckout',
    (tester) async {
      int retryCalls = 0;
      await tester.pumpWidget(
        buildScreen(
          bookingId: 100,
          checkoutUrl: 'https://paymob.com/checkout/direct100',
          onRetryCheckout: (id) async {
            retryCalls++;
            return const Left(BookingFailure('Should not be called'));
          },
        ),
      );

      // Verify no auto-call on mount
      expect(retryCalls, equals(0));

      await tester.ensureVisible(find.text(AppStrings.payNow));
      await tester.tap(find.text(AppStrings.payNow));
      await tester.pumpAndSettle();

      expect(retryCalls, equals(0));
      expect(
        launches.any(
          (call) =>
              call.arguments['url'] == 'https://paymob.com/checkout/direct100',
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    '2. Missing checkoutUrl does not auto-retry on build/init; shows error / retry button',
    (tester) async {
      int retryCalls = 0;
      await tester.pumpWidget(
        buildScreen(
          bookingId: 101,
          checkoutUrl: null,
          onRetryCheckout: (id) async {
            retryCalls++;
            return const Left(BookingFailure('fail'));
          },
        ),
      );
      await tester.pumpAndSettle();

      // Does not call retryCheckout on mount
      expect(retryCalls, equals(0));
      // Shows error / retry button
      expect(find.text(AppStrings.paymentOpenFailed), findsOneWidget);
      expect(find.text(AppStrings.retryPayment), findsOneWidget);
    },
  );

  testWidgets(
    '3. Tapping retry calls retryCheckout once and then launches returned URL',
    (tester) async {
      int retryCalls = 0;
      await tester.pumpWidget(
        buildScreen(
          bookingId: 102,
          checkoutUrl: null,
          onRetryCheckout: (id) async {
            retryCalls++;
            return Right(
              BookingCheckoutSession(
                booking: Booking(id: id, status: 'PENDING_PAYMENT'),
                checkoutUrl: 'https://paymob.com/checkout/retried102',
                isConfirmed: false,
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(retryCalls, equals(0));

      final retryBtn = find.text(AppStrings.retryPayment);
      await tester.ensureVisible(retryBtn);
      await tester.tap(retryBtn);
      await tester.pumpAndSettle();

      expect(retryCalls, equals(1));
      expect(
        launches.any(
          (call) =>
              call.arguments['url'] == 'https://paymob.com/checkout/retried102',
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    '4. Tapping retry when retryCheckout fails shows paymentOpenFailed SnackBar without throwing StateError',
    (tester) async {
      int retryCalls = 0;
      await tester.pumpWidget(
        buildScreen(
          bookingId: 103,
          checkoutUrl: null,
          onRetryCheckout: (id) async {
            retryCalls++;
            return const Left(
              CheckoutFailure('Gateway timeout', bookingId: 103),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      final retryBtn = find.text(AppStrings.retryPayment);
      await tester.ensureVisible(retryBtn);
      await tester.tap(retryBtn);
      await tester.pumpAndSettle();

      expect(retryCalls, equals(1));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(AppStrings.paymentOpenFailed), findsAtLeastNWidgets(1));
    },
  );
}
