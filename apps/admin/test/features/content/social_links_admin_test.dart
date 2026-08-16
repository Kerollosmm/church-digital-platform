import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/content/content_repository.dart';
import '../../helpers/fake_supabase.dart';

void main() {
  group('Admin ContentRepository Social Links', () {
    test('socialLinks lists rows ordered by position', () async {
      final fake = FakeSupabase({
        'social_links': [
          {
            'id': 1,
            'platform': 'YOUTUBE',
            'title_ar': 'يوتيوب',
            'url': 'https://youtube.com',
            'position': 1,
            'is_active': true,
          },
          {
            'id': 2,
            'platform': 'FACEBOOK',
            'title_ar': 'فيسبوك',
            'url': 'https://facebook.com',
            'position': 2,
            'is_active': true,
          },
        ],
      });

      final repo = ContentRepository(fake);
      final list = await repo.socialLinks();

      expect(list.length, 2);
      expect(list.first['platform'], 'YOUTUBE');
      expect(list.last['platform'], 'FACEBOOK');
    });

    test('createSocialLink inserts into social_links table', () async {
      final fake = FakeSupabase({
        'social_links': [],
      });

      final repo = ContentRepository(fake);
      await repo.createSocialLink({
        'platform': 'WHATSAPP',
        'title_ar': 'واتساب الكنيسة',
        'url': 'https://wa.me/201000000000',
        'position': 1,
        'is_active': true,
      });

      expect(fake.data['social_links']!.length, 1);
      expect(fake.data['social_links']!.first['platform'], 'WHATSAPP');
    });

    test('deleteSocialLink removes row by id', () async {
      final fake = FakeSupabase({
        'social_links': [
          {
            'id': 10,
            'platform': 'MAPS',
            'title_ar': 'الموقع',
            'url': 'https://maps.google.com',
          },
        ],
      });

      final repo = ContentRepository(fake);
      await repo.deleteSocialLink(10);

      expect(fake.data['social_links']!.isEmpty, isTrue);
    });
  });
}
