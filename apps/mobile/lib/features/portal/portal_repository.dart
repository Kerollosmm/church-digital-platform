import '../../services/app_supabase.dart';
import 'portal_models.dart';

abstract class PortalRepository {
  factory PortalRepository(AppSupabase db) = SupabasePortalRepository;

  Future<List<TodayScheduleItem>> todaySchedule();
  Future<List<AnnouncementItem>> announcements();
  Future<List<PriestItem>> priests();
}

class SupabasePortalRepository implements PortalRepository {
  SupabasePortalRepository(this._db);
  final AppSupabase _db;

  @override
  Future<List<TodayScheduleItem>> todaySchedule() async {
    final rows = await _db.query('v_schedule_today', orderBy: 'starts_at');
    return rows.map(TodayScheduleItem.fromJson).toList();
  }

  @override
  Future<List<AnnouncementItem>> announcements() async {
    final rows = await _db.query(
      'announcements',
      orderBy: 'published_at',
      ascending: false,
    );
    return rows.map(AnnouncementItem.fromJson).toList();
  }

  @override
  Future<List<PriestItem>> priests() async {
    final rows = await _db.query('v_priests', orderBy: 'name');
    return rows.map(PriestItem.fromJson).toList();
  }
}

class EmptyPortalRepository implements PortalRepository {
  @override
  Future<List<TodayScheduleItem>> todaySchedule() async => [];
  @override
  Future<List<AnnouncementItem>> announcements() async => [];
  @override
  Future<List<PriestItem>> priests() async => [];
}
