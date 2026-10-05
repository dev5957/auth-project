import '../../chronique/models/chronique.dart';
import '../../chronique/models/chronique_page.dart';

class CommunityCommentAuthor {
  const CommunityCommentAuthor({
    required this.userId,
    required this.login,
    required this.isFormerMember,
  });

  final int userId;
  final String login;
  final bool isFormerMember;

  factory CommunityCommentAuthor.fromJson(Map<String, dynamic> json) {
    return CommunityCommentAuthor(
      userId: parseChroniqueId(json['user_id']),
      login: json['login'] is String ? json['login'] as String : 'unknown',
      isFormerMember: json['is_former_member'] == true,
    );
  }

  String get displayLabel => isFormerMember ? '$login — ancien membre' : login;
}

class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.communityId,
    required this.communityPublicationId,
    required this.body,
    required this.status,
    required this.author,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  final int id;
  final int communityId;
  final int communityPublicationId;
  final String body;
  final String status;
  final CommunityCommentAuthor author;
  final String? createdAt;
  final String? updatedAt;
  final String? deletedAt;

  bool get isVisible => status == 'visible';
  bool get isModerated => status == 'moderated';

  factory CommunityComment.fromJson(Map<String, dynamic> json) {
    final authorRaw = json['author'];
    if (authorRaw is! Map) {
      throw const FormatException('Invalid community comment author');
    }
    return CommunityComment(
      id: parseChroniqueId(json['id']),
      communityId: parseChroniqueId(json['community_id']),
      communityPublicationId: parseChroniqueId(json['community_publication_id']),
      body: json['body'] is String ? json['body'] as String : '',
      status: json['status'] is String ? json['status'] as String : '',
      createdAt: json['created_at'] is String ? json['created_at'] as String : null,
      updatedAt: json['updated_at'] is String ? json['updated_at'] as String : null,
      deletedAt: json['deleted_at'] is String ? json['deleted_at'] as String : null,
      author: CommunityCommentAuthor.fromJson(Map<String, dynamic>.from(authorRaw)),
    );
  }
}

class CommunityCommentPage {
  const CommunityCommentPage({required this.items, this.next});

  final List<CommunityComment> items;
  final ChroniqueCursor? next;

  factory CommunityCommentPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid community comment list');
    }
    return CommunityCommentPage(
      items: [
        for (final item in items)
          if (item is Map) CommunityComment.fromJson(Map<String, dynamic>.from(item)),
      ],
      next: json['next'] is Map
          ? ChroniqueCursor.fromJson(Map<String, dynamic>.from(json['next'] as Map))
          : null,
    );
  }
}

class CommunityLikeState {
  const CommunityLikeState({
    required this.liked,
    required this.likeCount,
    required this.likedByMe,
  });

  final bool liked;
  final int likeCount;
  final bool likedByMe;

  factory CommunityLikeState.fromJson(Map<String, dynamic> json) {
    return CommunityLikeState(
      liked: json['liked'] == true,
      likeCount: json['like_count'] is int
          ? json['like_count'] as int
          : json['like_count'] is num
              ? (json['like_count'] as num).toInt()
              : 0,
      likedByMe: json['liked_by_me'] == true,
    );
  }
}

class CommunityCommentTrace {
  const CommunityCommentTrace({
    required this.id,
    required this.communityId,
    required this.commentId,
    required this.commentBody,
    required this.isEphemeral,
    this.communityPublicationId,
    this.publicationAuthorLogin,
    this.publishedAt,
    this.expiredAt,
    this.commentCreatedAt,
  });

  final int id;
  final int communityId;
  final int? communityPublicationId;
  final int commentId;
  final String commentBody;
  final bool isEphemeral;
  final String? publicationAuthorLogin;
  final String? publishedAt;
  final String? expiredAt;
  final String? commentCreatedAt;

  factory CommunityCommentTrace.fromJson(Map<String, dynamic> json) {
    final author = json['publication_author'];
    return CommunityCommentTrace(
      id: parseChroniqueId(json['id']),
      communityId: parseChroniqueId(json['community_id']),
      communityPublicationId:
          json['community_publication_id'] == null ? null : parseChroniqueId(json['community_publication_id']),
      commentId: parseChroniqueId(json['comment_id']),
      commentBody: json['comment_body'] is String ? json['comment_body'] as String : '',
      isEphemeral: json['is_ephemeral'] != false,
      publicationAuthorLogin: author is Map && author['login'] is String ? author['login'] as String : null,
      publishedAt: json['published_at'] is String ? json['published_at'] as String : null,
      expiredAt: json['expired_at'] is String ? json['expired_at'] as String : null,
      commentCreatedAt: json['comment_created_at'] is String ? json['comment_created_at'] as String : null,
    );
  }
}

class CommunityCommentTracePage {
  const CommunityCommentTracePage({required this.items, this.next});

  final List<CommunityCommentTrace> items;
  final ChroniqueCursor? next;

  factory CommunityCommentTracePage.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid community comment trace list');
    }
    return CommunityCommentTracePage(
      items: [
        for (final item in items)
          if (item is Map) CommunityCommentTrace.fromJson(Map<String, dynamic>.from(item)),
      ],
      next: json['next'] is Map
          ? ChroniqueCursor.fromJson(Map<String, dynamic>.from(json['next'] as Map))
          : null,
    );
  }
}

abstract final class CommunityCommentFields {
  static const int minRunes = 2;
  static const int maxRunes = 200;

  static String? bodyError(String? value) {
    final trimmed = value?.trim() ?? '';
    final length = trimmed.runes.length;
    if (length < minRunes || length > maxRunes) {
      return 'Le commentaire doit contenir entre $minRunes et $maxRunes caractères.';
    }
    return null;
  }
}
