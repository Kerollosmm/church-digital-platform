class ContentRepository {
  ContentRepository(this._db);
  final dynamic _db;

  Future<List<Map<String, dynamic>>> faq() async =>
      ((await _db.from('faq').select().order('position')) as List)
          .map((r) => Map<String, dynamic>.from(r as Map)).toList();

  Future<void> createFaq(Map<String, dynamic> row) async =>
      _db.from('faq').insert(row);

  Future<void> deleteFaq(int id) async => _db.from('faq').delete().eq('id', id);

  Future<List<Map<String, dynamic>>> socialLinks() async =>
      ((await _db.from('social_links').select().order('position')) as List)
          .map((r) => Map<String, dynamic>.from(r as Map)).toList();

  Future<void> createSocialLink(Map<String, dynamic> row) async =>
      _db.from('social_links').insert(row);

  Future<void> deleteSocialLink(int id) async =>
      _db.from('social_links').delete().eq('id', id);
}

