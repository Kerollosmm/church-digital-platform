import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/content/content_repository.dart';
import '../../helpers/mock_supabase.dart';

void main() {
  group('ContentRepository', () {
    test('faq returns sorted items or failure', () async {
      final mock = MockSupabase(tables: {
        'faq': [
          {'id': 2, 'question_ar': 'سؤال 2', 'position': 2},
          {'id': 1, 'question_ar': 'سؤال 1', 'position': 1},
        ],
      });
      final repo = ContentRepository(mock.build());
      final res = await repo.faq();
      expect(res.isRight, isTrue);
      final list = res.fold((f) => <Map<String, dynamic>>[], (r) => r);
      expect(list.length, 2);
    });

    test('createFaq and deleteFaq mutations succeed', () async {
      final mock = MockSupabase(tables: {
        'faq': [],
      });
      final repo = ContentRepository(mock.build());
      final createRes = await repo.createFaq({'id': 10, 'question_ar': 'سؤال جديد'});
      expect(createRes.isRight, isTrue);
      expect(mock.data['faq']!.length, 1);

      final deleteRes = await repo.deleteFaq(10);
      expect(deleteRes.isRight, isTrue);
      expect(mock.data['faq']!.isEmpty, isTrue);
    });

    test('socialLinks CRUD works', () async {
      final mock = MockSupabase(tables: {
        'social_links': [],
      });
      final repo = ContentRepository(mock.build());
      final createRes = await repo.createSocialLink({'id': 1, 'platform': 'facebook', 'url': 'https://fb.com'});
      expect(createRes.isRight, isTrue);

      final listRes = await repo.socialLinks();
      expect(listRes.isRight, isTrue);
      expect(listRes.fold((f) => <Map<String, dynamic>>[], (r) => r).length, 1);

      final deleteRes = await repo.deleteSocialLink(1);
      expect(deleteRes.isRight, isTrue);
      expect(mock.data['social_links']!.isEmpty, isTrue);
    });
  });
}
