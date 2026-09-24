import 'chronique.dart';

const _monthLabels = <String>[
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

/// Date affichée : `published_at` si active, `archived_at` si archivée.
String? chroniqueDisplayInstant(Chronique chronique) {
  if (chronique.status == 'archived') {
    final archived = chronique.archivedAt?.trim();
    if (archived != null && archived.isNotEmpty) {
      return archived;
    }
  }
  final published = chronique.publishedAt?.trim();
  if (published != null && published.isNotEmpty) {
    return published;
  }
  final created = chronique.createdAt?.trim();
  if (created != null && created.isNotEmpty) {
    return created;
  }
  return null;
}

/// Exemple : `23 sept. 2026 • 15:57` (heure locale, sans secondes).
String formatChroniqueDateTime(DateTime date) {
  final local = date.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = _monthLabels[local.month - 1];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day $month ${local.year} • $hour:$minute';
}

String chroniqueDateLabel(Chronique chronique) {
  final raw = chroniqueDisplayInstant(chronique);
  if (raw == null || raw.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  return formatChroniqueDateTime(parsed);
}
