import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/portal/portal_models.dart';
import 'package:mobile/features/portal/portal_repository.dart';
import 'package:mobile/services/app_supabase.dart';

class FakePortalSupabase implements AppSupabase {
  final Map<String, List<Map<String, dynamic>>> tables;

  FakePortalSupabase(this.tables);

  @override
  Future<List<Map<String, dynamic>>> query(
    String table, {
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
  }) async {
    return tables[table] ?? [];
  }

  @override
  Future<Object?> rpc(String fn, Map<String, dynamic> params) async => null;

  @override
  Future<Map<String, dynamic>> invokeFunction(
    String fn, {
    Map<String, dynamic>? body,
  }) async => {};

  @override
  Future<String> uploadStorage(
    String bucket,
    String path,
    List<int> bytes, {
    String? contentType,
  }) async => path;

  @override
  Future<void> deleteStorage(String bucket, String path) async {}
}

void main() {
  group('PortalRepository Social Links', () {
    test('SocialLinkItem.fromJson parses valid fields correctly', () {
      final json = {
        'id': 10,
        'platform': 'YOUTUBE',
        'title_ar': 'قناة الكنيسة',
        'url': 'https://youtube.com/@church',
        'icon_name': 'video_library',
        'position': 1,
      };

      final item = SocialLinkItem.fromJson(json);

      expect(item.id, 10);
      expect(item.platform, 'YOUTUBE');
      expect(item.titleAr, 'قناة الكنيسة');
      expect(item.url, 'https://youtube.com/@church');
      expect(item.iconName, 'video_library');
      expect(item.position, 1);
    });

    test(
      'SupabasePortalRepository.socialLinks queries social_links table and maps entities',
      () async {
        final fakeDb = FakePortalSupabase({
          'social_links': [
            {
              'id': 1,
              'platform': 'FACEBOOK',
              'title_ar': 'الصفحة الرسمية',
              'url': 'https://facebook.com/church',
              'icon_name': 'facebook',
              'position': 1,
            },
            {
              'id': 2,
              'platform': 'MAPS',
              'title_ar': 'موقع الكنيسة',
              'url': 'https://maps.google.com/?q=church',
              'icon_name': 'location_on',
              'position': 2,
            },
          ],
        });

        final repo = SupabasePortalRepository(fakeDb);
        final links = await repo.socialLinks();

        expect(links.length, 2);
        expect(links.first.platform, 'FACEBOOK');
        expect(links.first.titleAr, 'الصفحة الرسمية');
        expect(links.last.platform, 'MAPS');
        expect(links.last.url, 'https://maps.google.com/?q=church');
      },
    );

    test('EmptyPortalRepository returns empty list for socialLinks', () async {
      final emptyRepo = EmptyPortalRepository();
      final links = await emptyRepo.socialLinks();
      expect(links, isEmpty);
    });
  });
}
