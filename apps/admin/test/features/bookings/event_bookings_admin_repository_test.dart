import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/bookings/event_bookings_admin_repository.dart';
import '../../helpers/mock_supabase.dart';

void main() {
  group('SupabaseEventBookingsAdminRepository', () {
    test('fetchVenues returns active venues', () async {
      final mock = MockSupabase(
        tables: {
          'venues_resources': [
            {
              'id': 'v-1',
              'name_ar': 'القاعة الكبرى',
              'location_details_ar': 'الدور الأرضي',
              'is_active': true,
            },
          ],
        },
      );

      final repo = SupabaseEventBookingsAdminRepository(client: mock.build());
      final res = await repo.fetchVenues();

      expect(res.isRight, isTrue);
      res.fold((f) => fail('expected success: ${f.message}'), (venues) {
        expect(venues.length, equals(1));
        expect(venues.first.nameAr, equals('القاعة الكبرى'));
      });
    });

    test(
      'getAvailablePriests invokes RPC and returns list of priests',
      () async {
        final mock = MockSupabase(
          rpc: {
            'get_available_priests': (args) async => [
              {
                'id': 101,
                'name': 'أبونا أنطونيوس',
                'phone': '+201011117501',
                'rank': 'HEGUMEN',
                'active_bookings_count': 0,
              },
            ],
          },
        );

        final repo = SupabaseEventBookingsAdminRepository(client: mock.build());
        final res = await repo.getAvailablePriests(
          startTime: DateTime(2026, 9, 10, 10, 0),
          endTime: DateTime(2026, 9, 10, 12, 0),
        );

        expect(res.isRight, isTrue);
        res.fold((f) => fail('expected success: ${f.message}'), (priests) {
          expect(priests.length, equals(1));
          expect(priests.first.name, equals('أبونا أنطونيوس'));
          expect(priests.first.rank, equals('HEGUMEN'));
        });
      },
    );

    test(
      'assignPriestAndVenue invokes admin_assign_priest_and_venue RPC',
      () async {
        Map<String, dynamic>? calledArgs;
        final mock = MockSupabase(
          rpc: {
            'admin_assign_priest_and_venue': (args) async {
              calledArgs = args;
              return {'success': true, 'booking_id': args['p_booking_id']};
            },
          },
        );

        final repo = SupabaseEventBookingsAdminRepository(client: mock.build());
        final res = await repo.assignPriestAndVenue(
          bookingId: 'b-999',
          venueId: 'v-111',
          priestId: 7501,
          overrideNotes: 'ملاحظة',
        );

        expect(res.isRight, isTrue);
        expect(calledArgs, isNotNull);
        expect(calledArgs!['p_booking_id'], equals('b-999'));
        expect(calledArgs!['p_venue_id'], equals('v-111'));
        expect(calledArgs!['p_priest_id'], equals(7501));
        expect(calledArgs!['p_override_notes'], equals('ملاحظة'));
      },
    );
  });
}
