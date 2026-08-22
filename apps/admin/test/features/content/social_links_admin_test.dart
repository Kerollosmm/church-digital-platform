import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/content/content_repository.dart';
import '../../helpers/mock_supabase.dart';

void main() {
  group('Admin ContentRepository Social Links', () {
    test('socialLinks lists rows ordered by position', () async {
      final mock = MockSupabase(tables: {
        'social_links': [
          {
            'id': 1,
            'platform': 'YOUTUBE',
            'title_ar': 'قناة الكنيسة',
            'url': 'https://youtube.com',
            'position': 1,
            'is_active': true,
          },
          {
            'id': 2,
            'platform': 'FACEBOOK',
            'title_ar': 'صفحة فيسبوك',
            'url': 'https://facebook.com',
            'position': 2,
            'is_active': true,
          },
        ],
      });

      final repo = ContentRepository(mock.build());
      final list = (await repo.socialLinks()).fold((f) => throw f, (r) => r);

      expect(list.length, 2);
      expect(list.first['platform'], 'YOUTUBE');
      expect(list.last['platform'], 'FACEBOOK');
    });

    test('createSocialLink inserts into social_links table', () async {
      final mock = MockSupabase(tables: {
        'social_links': [],
      });

      final repo = ContentRepository(mock.build());
      final outcome = await repo.createSocialLink({
        'platform': 'WHATSAPP',
        'title_ar': 'قناة واتساب الرسمية',
        'url': 'https://wa.me/201000000000',
        'position': 1,
        'is_active': true,
      });
      outcome.fold((f) => throw f, (_) => {});

      expect(mock.data['social_links']!.length, 1);
      expect(mock.data['social_links']!.first['platform'], 'WHATSAPP');
    });

    test('deleteSocialLink removes row by id', () async {
      final mock = MockSupabase(tables: {
        'social_links': [
          {
            'id': 10,
            'platform': 'MAPS',
            'title_ar': 'الموقع على الخريطة',
            'url': 'https://maps.google.com',
          },
        ],
      });

      final repo = ContentRepository(mock.build());
      final outcome = await repo.deleteSocialLink(10);
      outcome.fold((f) => throw f, (_) => {});

      expect(mock.data['social_links']!.isEmpty, isTrue);
    });
  });
}
