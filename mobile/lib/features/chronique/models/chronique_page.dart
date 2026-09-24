import 'chronique.dart';

/// Curseur de page GET /chroniques. Non consommé par l’UI V1.
class ChroniqueCursor {
  const ChroniqueCursor({
    required this.beforeAt,
    required this.beforeId,
  });

  final String beforeAt;
  final int beforeId;

  factory ChroniqueCursor.fromJson(Map<String, dynamic> json) {
    final beforeAt = json['before_at'];
    if (beforeAt is! String || beforeAt.isEmpty) {
      throw const FormatException('Invalid chronique cursor');
    }
    return ChroniqueCursor(
      beforeAt: beforeAt,
      beforeId: parseChroniqueId(json['before_id']),
    );
  }
}

/// Première page du fil. `next` prépare la pagination, sans l’activer.
class ChroniquePage {
  const ChroniquePage({
    required this.items,
    this.next,
  });

  final List<Chronique> items;
  final ChroniqueCursor? next;

  factory ChroniquePage.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid chronique list payload');
    }
    final nextRaw = json['next'];
    ChroniqueCursor? next;
    if (nextRaw != null) {
      if (nextRaw is! Map) {
        throw const FormatException('Invalid chronique cursor');
      }
      next = ChroniqueCursor.fromJson(Map<String, dynamic>.from(nextRaw));
    }
    return ChroniquePage(
      items: [
        for (final item in items) Chronique.fromJson(asChroniqueJson(item)),
      ],
      next: next,
    );
  }
}

Map<String, dynamic> asChroniqueJson(Object? data) {
  if (data is Map<String, dynamic>) {
    return data;
  }
  if (data is Map) {
    return Map<String, dynamic>.from(data);
  }
  throw const FormatException('Invalid chronique payload');
}
