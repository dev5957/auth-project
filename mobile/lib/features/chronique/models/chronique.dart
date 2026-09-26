/// Ressource publique `chronique` (POST/GET/PATCH). Pas de `user_id`.
class Chronique {
  const Chronique({
    required this.id,
    required this.body,
    required this.status,
    this.themeId,
    this.title,
    this.publishedAt,
    this.archivedAt,
    this.createdAt,
    this.updatedAt,
    this.scheduledAt,
    this.expiresAt,
    this.expiredAt,
    this.isTimeLimited = false,
    this.media = const [],
  });

  final int id;
  final int? themeId;
  final String? title;
  final String body;
  final String status;
  final String? publishedAt;
  final String? archivedAt;
  final String? createdAt;
  final String? updatedAt;
  final DateTime? scheduledAt;
  final DateTime? expiresAt;
  final DateTime? expiredAt;
  final bool isTimeLimited;
  final List<ChroniqueMedia> media;

  Chronique copyWith({
    int? id,
    int? themeId,
    String? title,
    String? body,
    String? status,
    String? publishedAt,
    String? archivedAt,
    String? createdAt,
    String? updatedAt,
    DateTime? scheduledAt,
    DateTime? expiresAt,
    DateTime? expiredAt,
    bool? isTimeLimited,
    List<ChroniqueMedia>? media,
    bool clearTitle = false,
  }) {
    return Chronique(
      id: id ?? this.id,
      themeId: themeId ?? this.themeId,
      title: clearTitle ? null : (title ?? this.title),
      body: body ?? this.body,
      status: status ?? this.status,
      publishedAt: publishedAt ?? this.publishedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      expiresAt: expiresAt ?? this.expiresAt,
      expiredAt: expiredAt ?? this.expiredAt,
      isTimeLimited: isTimeLimited ?? this.isTimeLimited,
      media: media ?? this.media,
    );
  }

  factory Chronique.fromJson(Map<String, dynamic> json) {
    final body = json['body'];
    final status = json['status'];
    if (body is! String || status is! String) {
      throw const FormatException('Invalid chronique payload');
    }
    return Chronique(
      id: parseChroniqueId(json['id']),
      themeId: json['theme_id'] == null ? null : parseChroniqueId(json['theme_id']),
      title: json['title'] as String?,
      body: body,
      status: status,
      publishedAt: json['published_at'] as String?,
      archivedAt: json['archived_at'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      scheduledAt: parseChroniqueDateTime(json['scheduled_at']),
      expiresAt: parseChroniqueDateTime(json['expires_at']),
      expiredAt: parseChroniqueDateTime(json['expired_at']),
      isTimeLimited: json['is_time_limited'] == true,
      media: parseChroniqueMediaList(json['media']),
    );
  }
}

/// Métadonnées média renvoyées par l’API (lecture seule côté édition V1).
class ChroniqueMedia {
  const ChroniqueMedia({
    required this.kind,
    this.id,
    this.originalFilename,
    this.byteSize,
    this.status,
    this.contentType,
    this.sortOrder,
    this.readUrl,
    this.readExpiresAt,
  });

  final int? id;
  final String kind;
  final String? originalFilename;
  final int? byteSize;
  final String? status;
  final String? contentType;
  final int? sortOrder;

  /// URL GET signée R2, temporaire. Jamais persistée.
  final String? readUrl;
  final DateTime? readExpiresAt;

  factory ChroniqueMedia.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    if (kind is! String || kind.isEmpty) {
      throw const FormatException('Invalid media payload');
    }
    return ChroniqueMedia(
      id: json['id'] == null ? null : parseChroniqueId(json['id']),
      kind: kind,
      originalFilename: json['original_filename'] as String?,
      byteSize: _parseByteSize(json['byte_size']),
      status: json['status'] as String?,
      contentType: json['content_type'] as String?,
      sortOrder: _parseByteSize(json['sort_order']),
      readUrl: _parseOptionalUrl(json['read_url']),
      readExpiresAt: parseChroniqueDateTime(json['read_expires_at']),
    );
  }
}

String? _parseOptionalUrl(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

int? _parseByteSize(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

List<ChroniqueMedia> parseChroniqueMediaList(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  final items = <ChroniqueMedia>[];
  for (final item in raw) {
    if (item is! Map) {
      continue;
    }
    try {
      items.add(ChroniqueMedia.fromJson(Map<String, dynamic>.from(item)));
    } on FormatException {
      continue;
    }
  }
  return items;
}

int parseChroniqueId(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw const FormatException('Invalid integer id');
}

DateTime? parseChroniqueDateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return DateTime.tryParse(trimmed);
  }
  return null;
}
