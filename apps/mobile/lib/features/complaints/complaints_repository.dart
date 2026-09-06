import '../../services/app_supabase.dart';
import 'complaints_models.dart';

abstract interface class ComplaintsRepository {
  Future<List<ComplaintItem>> myComplaints();
  Future<int> submitComplaint({required String category, required String body});
}

class SupabaseComplaintsRepository implements ComplaintsRepository {
  SupabaseComplaintsRepository(this._db);
  final AppSupabase _db;

  @override
  Future<List<ComplaintItem>> myComplaints() async {
    final rows = await _db.query(
      'v_my_complaints',
      orderBy: 'created_at',
      ascending: false,
    );
    return rows.map(ComplaintItem.fromJson).toList();
  }

  @override
  Future<int> submitComplaint({
    required String category,
    required String body,
  }) async {
    final res = await _db.rpc('submit_complaint_secure', {
      'p_category': category,
      'p_body': body,
    });
    if (res is int) return res;
    if (res is num) return res.toInt();
    if (res is String) return int.tryParse(res) ?? 0;
    return 0;
  }
}

class EmptyComplaintsRepository implements ComplaintsRepository {
  @override
  Future<List<ComplaintItem>> myComplaints() async => [];
  @override
  Future<int> submitComplaint({
    required String category,
    required String body,
  }) async => 0;
}
