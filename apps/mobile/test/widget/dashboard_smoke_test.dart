import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/service_locator.dart';
import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

void main() {
  testWidgets('dashboard renders bookings from fake repository', (
    tester,
  ) async {
    final fake = FakeBookingRepository(bookings: [fakeBooking]);
    await tester.pumpWidget(
      TestApp(deps: AppDependencies.forTest(bookingRepository: fake)),
    );
    await tester.pumpAndSettle();
    expect(find.text(fakeBooking.serviceName), findsOneWidget);
  });
}
