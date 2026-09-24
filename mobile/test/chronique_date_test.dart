import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/models/chronique_date.dart';

void main() {
  test('active chroniques use published_at as day, month, year, hour and minute', () {
    const chronique = Chronique(
      id: 1,
      body: 'Le texte de la chronique, d au moins vingt caracteres.',
      status: 'active',
      publishedAt: '2026-09-23T15:57:30.000Z',
      createdAt: '2026-01-01T00:00:00.000Z',
    );
    final label = chroniqueDateLabel(chronique);
    final local = DateTime.parse('2026-09-23T15:57:30.000Z').toLocal();
    final expectedHour = local.hour.toString().padLeft(2, '0');
    final expectedMinute = local.minute.toString().padLeft(2, '0');
    expect(label, contains('sept.'));
    expect(label, contains('2026'));
    expect(label, contains('•'));
    expect(label, endsWith('$expectedHour:$expectedMinute'));
    expect(label.contains(':$expectedMinute:'), isFalse);
    expect(RegExp(r'• \d{2}:\d{2}$').hasMatch(label), isTrue);
  });

  test('archived chroniques use archived_at not created_at', () {
    const chronique = Chronique(
      id: 2,
      body: 'Le texte de la chronique, d au moins vingt caracteres.',
      status: 'archived',
      publishedAt: '2026-09-01T08:00:00.000Z',
      archivedAt: '2026-10-02T09:05:00.000Z',
      createdAt: '2026-01-01T00:00:00.000Z',
    );
    final label = chroniqueDateLabel(chronique);
    final local = DateTime.parse('2026-10-02T09:05:00.000Z').toLocal();
    expect(label, contains('oct.'));
    expect(label, contains('2026'));
    expect(label, endsWith(
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
    ));
    expect(label.contains('08:00'), isFalse);
  });
}
