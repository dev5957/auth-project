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
  });

  final int? id;
  final String kind;
  final String? originalFilename;
  final int? byteSize;
  final String? status;

  factory ChroniqueMedia.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    if (kind is! String || kind.isEmpty) {
      throw const FormatException('Invalid media payload');
    }
    return ChroniqueMedia(
      id: json['id'] == null ? null : parseChroniqueId(json['id']),
      kind: kind,
      originalFilename: json['original_filename'] as String?,
      byteSize: json['byte_size'] is int ? json['byte_size'] as int : null,
      status: json['status'] as String?,
    );
  }
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
