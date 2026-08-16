class AnnouncementItem {
  final String titleAr;
  final String bodyAr;
  final String? categoryAr;

  const AnnouncementItem({
    required this.titleAr,
    required this.bodyAr,
    this.categoryAr,
  });

  factory AnnouncementItem.fromJson(Map<String, dynamic> json) =>
      AnnouncementItem(
        titleAr: json['title_ar'] as String? ?? '',
        bodyAr: json['body_ar'] as String? ?? '',
        categoryAr: json['category_ar'] as String?,
      );
}

class TodayScheduleItem {
  final int id;
  final String titleAr;
  final DateTime startsAt;
  final DateTime endsAt;

  const TodayScheduleItem({
    required this.id,
    required this.titleAr,
    required this.startsAt,
    required this.endsAt,
  });

  factory TodayScheduleItem.fromJson(
    Map<String, dynamic> json,
  ) => TodayScheduleItem(
    id: ((json['slot_id'] ?? json['id']) as num?)?.toInt() ?? 0,
    titleAr: json['title_ar'] as String? ?? '',
    startsAt:
        DateTime.tryParse(json['starts_at'] as String? ?? '') ?? DateTime.now(),
    endsAt:
        DateTime.tryParse(json['ends_at'] as String? ?? '') ?? DateTime.now(),
  );
}

class PriestItem {
  final String id;
  final String name;
  final String? photoUrl;
  final String? bio;
  final String? visitationHours;

  const PriestItem({
    required this.id,
    required this.name,
    this.photoUrl,
    this.bio,
    this.visitationHours,
  });

  factory PriestItem.fromJson(Map<String, dynamic> json) => PriestItem(
    id: json['id']?.toString() ?? '',
    name: json['name'] as String? ?? '',
    photoUrl: json['photo_url'] as String?,
    bio: json['bio'] as String?,
    visitationHours: json['visitation_hours'] as String?,
  );
}

class SocialLinkItem {
  final int id;
  final String platform;
  final String titleAr;
  final String url;
  final String? iconName;
  final int position;

  const SocialLinkItem({
    required this.id,
    required this.platform,
    required this.titleAr,
    required this.url,
    this.iconName,
    this.position = 0,
  });

  factory SocialLinkItem.fromJson(Map<String, dynamic> json) => SocialLinkItem(
    id: (json['id'] as num?)?.toInt() ?? 0,
    platform: json['platform'] as String? ?? '',
    titleAr: json['title_ar'] as String? ?? '',
    url: json['url'] as String? ?? '',
    iconName: json['icon_name'] as String?,
    position: (json['position'] as num?)?.toInt() ?? 0,
  );
}

