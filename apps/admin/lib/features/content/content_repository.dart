class ContentRepository {
  ContentRepository(this._db);
  final dynamic _db;

  Future<List<Map<String, dynamic>>> faq() async =>
      ((await _db.from('faq').select().order('position')) as List)
          .map((r) => Map<String, dynamic>.from(r as Map)).toList();

  Future<void> createFaq(Map<String, dynamic> row) async =>
      _db.from('faq').insert(row);

  Future<void> deleteFaq(int id) async => _db.from('faq').delete().eq('id', id);
}
