import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/video/video_purchase_screen.dart';
import 'package:mobile/features/booking/payment_redirect_screen.dart';
import 'package:mobile/services/app_strings.dart';
import '../../helpers/fakes.dart';
import '../../helpers/pump_with_router.dart';
import '../../helpers/test_app_supabase.dart';

void main() {
  testWidgets(
    'featured card renders first row title and date, grid renders remaining rows',
    (tester) async {
      final fake = FakeVideosRepository(
        videos: [
          {
            'id': 1,
            'title_ar': 'قداس عيد الميلاد',
            'price': 100,
            'event_date': '2024-12-26T00:00:00Z',
            'privacy': 'PUBLIC',
          },
          {
            'id': 2,
            'title_ar': 'عظة البابا',
            'price': 50,
            'event_date': '2024-12-25T00:00:00Z',
            'privacy': 'PUBLIC',
          },
        ],
      );
      await tester.pumpWidget(
        MaterialApp(home: VideoPurchaseScreen(repository: fake)),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.videosStoreTitle), findsOneWidget);
      expect(find.text('قداس عيد الميلاد'), findsOneWidget);
      expect(find.text('2024-12-26'), findsOneWidget);
      expect(find.text(AppStrings.videosLibraryTitle), findsOneWidget);
      expect(find.text('عظة البابا'), findsOneWidget);
    },
  );

  testWidgets(
    'video purchase: buy button tap calls purchase_video and redirects',
    (tester) async {
      final fake = FakeVideosRepository(
        videos: [
          {
            'id': 1,
            'title_ar': 'قداس رئيسي',
            'price': 100,
            'event_date': '2024-12-26T00:00:00Z',
          },
          {
            'id': 5,
            'title_ar': 'عظة المولد',
            'price': 30,
            'event_date': '2024-12-25T00:00:00Z',
          },
        ],
        payment: {'id': 30},
      );
      final fakeDb = TestAppSupabase(
        {},
        rpcHandler: {
          'paymob-checkout': (_) async => {
            'checkout_url': 'https://paymob.test/x',
          },
        },
      );
      await pumpWithRouter(
        tester,
        home: VideoPurchaseScreen(repository: fake),
        db: fakeDb,
      );
      expect(find.text('عظة المولد'), findsOneWidget);
      final buyBtn = find.text(AppStrings.buyVideo);
      await tester.ensureVisible(buyBtn);
      await tester.tap(buyBtn);
      await tester.pumpAndSettle();
      expect(fake.purchaseCalls, [5]);
      expect(find.byType(PaymentRedirectScreen), findsOneWidget);
      expect(find.text('#30'), findsOneWidget);
    },
  );

  testWidgets(
    'purchased row (privacy UNLISTED) renders purchasedLabel and no buy button',
    (tester) async {
      final fake = FakeVideosRepository(
        videos: [
          {
            'id': 10,
            'title_ar': 'فيديو مميز',
            'price': 50,
            'event_date': '2024-12-26T00:00:00Z',
            'privacy': 'PUBLIC',
          },
          {
            'id': 11,
            'title_ar': 'فيديو مشتري',
            'price': 80,
            'event_date': '2024-12-25T00:00:00Z',
            'privacy': 'UNLISTED',
          },
        ],
      );
      await tester.pumpWidget(
        MaterialApp(home: VideoPurchaseScreen(repository: fake)),
      );
      await tester.pumpAndSettle();

      expect(find.text('فيديو مشتري'), findsOneWidget);
      expect(find.text(AppStrings.purchasedLabel), findsOneWidget);
      expect(find.text(AppStrings.buyVideo), findsNothing);
    },
  );

  testWidgets('empty videos shows AppStrings.videosEmpty', (tester) async {
    final fake = FakeVideosRepository(videos: []);
    await tester.pumpWidget(
      MaterialApp(home: VideoPurchaseScreen(repository: fake)),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.videosEmpty), findsOneWidget);
  });

  testWidgets('existing rows without privacy key are treated as purchasable', (
    tester,
  ) async {
    final fake = FakeVideosRepository(
      videos: [
        {
          'id': 10,
          'title_ar': 'فيديو مميز',
          'price': 50,
          'event_date': '2024-12-26T00:00:00Z',
        },
        {
          'id': 20,
          'title_ar': 'فيديو القداس',
          'price': 40,
          'event_date': '2024-12-25T00:00:00Z',
        },
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: VideoPurchaseScreen(repository: fake)),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.buyVideo), findsOneWidget);
    expect(find.text(AppStrings.purchasedLabel), findsNothing);
  });
}
