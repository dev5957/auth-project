import '../../chronique/models/chronique.dart';
import '../../chronique/models/chronique_page.dart';

class CommunityPublicationAuthor {
  const CommunityPublicationAuthor({
    required this.userId,
    required this.login,
    required this.isFormerMember,
  });

  final int userId;
  final String login;
  final bool isFormerMember;

  factory CommunityPublicationAuthor.fromJson(Map<String, dynamic> json) {
    return CommunityPublicationAuthor(
      userId: parseChroniqueId(json['user_id']),
      login: json['login'] is String ? json['login'] as String : 'unknown',
      isFormerMember: json['is_former_member'] == true,
    );
  }

  String get displayLabel => isFormerMember ? '$login — ancien membre' : login;
}

class CommunityPublication {
  const CommunityPublication({
    required this.id,
    required this.communityId,
    required this.author,
    required this.body,
    required this.status,
    this.communityName,
    this.title,
    this.scheduledAt,
    this.publishedAt,
    this.expiresAt,
    this.expiredAt,
    this.isTimeLimited = false,
    this.commentsEnabled = false,
    this.deletedByUserId,
    this.media = const [],
  });

  final int id;
  final int communityId;
  final String? communityName;
  final CommunityPublicationAuthor author;
  final String? title;
  final String body;
  final String status;
  final String? scheduledAt;
  final String? publishedAt;
  final String? expiresAt;
  final String? expiredAt;
  final bool isTimeLimited;
  final int? deletedByUserId;
  final bool commentsEnabled;
  final List<ChroniqueMedia> media;

  factory CommunityPublication.fromJson(Map<String, dynamic> json) {
    final authorRaw = json['author'];
    if (authorRaw is! Map) {
      throw const FormatException('Invalid community publication author');
    }
    final mediaRaw = json['media'];
    return CommunityPublication(
      id: parseChroniqueId(json['id']),
      communityId: parseChroniqueId(json['community_id']),
      communityName: json['community_name'] is String ? json['community_name'] as String : null,
      author: CommunityPublicationAuthor.fromJson(Map<String, dynamic>.from(authorRaw)),
      title: json['title'] is String ? json['title'] as String : null,
      body: json['body'] is String ? json['body'] as String : '',
      status: json['status'] is String ? json['status'] as String : '',
      scheduledAt: json['scheduled_at'] is String ? json['scheduled_at'] as String : null,
      publishedAt: json['published_at'] is String ? json['published_at'] as String : null,
      expiresAt: json['expires_at'] is String ? json['expires_at'] as String : null,
      expiredAt: json['expired_at'] is String ? json['expired_at'] as String : null,
      deletedByUserId: json['deleted_by_user_id'] == null
          ? null
          : parseChroniqueId(json['deleted_by_user_id']),
      isTimeLimited: json['is_time_limited'] == true,
      commentsEnabled: json['comments_enabled'] == true,
      media: mediaRaw is List
          ? [
              for (final item in mediaRaw)
                if (item is Map) ChroniqueMedia.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
    );
  }

  Chronique asChronique() {
    return Chronique(
      id: id,
      title: title,
      body: body,
      status: status,
      publishedAt: publishedAt,
      scheduledAt: scheduledAt == null ? null : DateTime.tryParse(scheduledAt!),
      expiresAt: expiresAt == null ? null : DateTime.tryParse(expiresAt!),
      expiredAt: expiredAt == null ? null : DateTime.tryParse(expiredAt!),
      isTimeLimited: isTimeLimited,
      media: media,
    );
  }
}

class CommunityPublicationPage {
  const CommunityPublicationPage({required this.items, this.next});

  final List<CommunityPublication> items;
  final ChroniqueCursor? next;

  factory CommunityPublicationPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid community publication list');
    }
    return CommunityPublicationPage(
      items: [
        for (final item in items)
          if (item is Map) CommunityPublication.fromJson(Map<String, dynamic>.from(item)),
      ],
      next: json['next'] is Map
          ? ChroniqueCursor.fromJson(Map<String, dynamic>.from(json['next'] as Map))
          : null,
    );
  }
}
