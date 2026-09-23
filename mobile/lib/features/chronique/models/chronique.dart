/// Ressource publique `chronique` (POST/GET). Pas de `user_id`.
class Chronique {
  const Chronique({
    required this.id,
    required this.body,
    required this.status,
    this.themeId,
    this.title,
    this.publishedAt,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int? themeId;
  final String? title;
  final String body;
  final String status;
  final String? publishedAt;
  final String? createdAt;
  final String? updatedAt;

  factory Chronique.fromJson(Map<String, dynamic> json) {
    final body = json['body'];
    final status = json['status'];
    if (body is! String || status is! String) {
      throw const FormatException('Invalid chronique payload');
    }
    return Chronique(
      id: _parseId(json['id']),
      themeId: json['theme_id'] == null ? null : _parseId(json['theme_id']),
      title: json['title'] as String?,
      body: body,
      status: status,
      publishedAt: json['published_at'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }
}

int _parseId(Object? value) {
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
