import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/models/chronique_date.dart';
import 'package:mobile/features/chronique/models/chronique_schedule_draft.dart';

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

  test('toUtcIso never sends a naive local timestamp', () {
    final local = DateTime(2026, 9, 24, 18, 30);
    final iso = ChroniqueDateHelper.toUtcIso(local);
    expect(iso.contains('Z'), isTrue);
    final parsed = DateTime.parse(iso);
    expect(parsed.isUtc, isTrue);
    expect(parsed, local.toUtc());
  });

  test('past scheduled local datetime is rejected', () {
    final now = DateTime(2026, 9, 24, 18, 30);
    expect(
      ChroniqueDateHelper.scheduleError(
        now.subtract(const Duration(minutes: 1)),
        now: now,
      ),
      kSchedulePastMessage,
    );
    expect(ChroniqueDateHelper.scheduleError(null, now: now), kScheduleRequiredMessage);
    expect(
      ChroniqueDateHelper.scheduleError(
        now.add(const Duration(hours: 1)),
        now: now,
      ),
      isNull,
    );
  });

  test('expiration before activation is rejected', () {
    final activation = DateTime(2026, 9, 24, 18, 30);
    expect(
      ChroniqueDateHelper.expirationError(
        preset: ChroniqueExpirationPreset.custom,
        activationLocal: activation,
        customLocal: activation.subtract(const Duration(minutes: 1)),
      ),
      kExpiresBeforeActivationMessage,
    );
    expect(
      ChroniqueDateHelper.expirationError(
        preset: ChroniqueExpirationPreset.custom,
        activationLocal: activation,
        customLocal: activation,
      ),
      kExpiresBeforeActivationMessage,
    );
    expect(
      ChroniqueDateHelper.expirationError(
        preset: ChroniqueExpirationPreset.oneHour,
        activationLocal: activation,
      ),
      isNull,
    );
  });

  test('scheduled and expired statuses format without throwing', () {
    final scheduled = Chronique(
      id: 3,
      body: 'Le texte de la chronique, d au moins vingt caracteres.',
      status: 'scheduled',
      scheduledAt: DateTime.parse('2026-09-24T16:30:00.000Z'),
    );
    expect(chroniqueDateLabel(scheduled), isNotEmpty);
    expect(chroniqueDateLabel(scheduled), contains('•'));

    final expired = Chronique(
      id: 4,
      body: 'Le texte de la chronique, d au moins vingt caracteres.',
      status: 'expired',
      publishedAt: '2026-09-20T10:00:00.000Z',
      isTimeLimited: true,
      expiresAt: DateTime.parse('2026-09-21T10:00:00.000Z'),
    );
    expect(chroniqueDateLabel(expired), isNotEmpty);
  });

  test('quick expiration is computed from scheduled activation not now', () {
    final scheduled = DateTime(2026, 9, 25, 14);
    final draft = ChroniqueScheduleDraft(
      publishMode: ChroniquePublishMode.schedule,
      scheduledAt: scheduled,
      expirationEnabled: true,
      expirationPreset: ChroniqueExpirationPreset.oneHour,
    );
    expect(draft.resolvedExpiresLocal(), DateTime(2026, 9, 25, 15));
    expect(draft.validationError(now: DateTime(2026, 9, 25, 10)), isNull);
  });

  test('30-day expiration is 30 days after activation', () {
    final activation = DateTime(2026, 9, 24, 18, 30);
    expect(
      ChroniqueDateHelper.resolveExpirationLocal(
        preset: ChroniqueExpirationPreset.thirtyDays,
        activationLocal: activation,
      ),
      DateTime(2026, 10, 24, 18, 30),
    );
    expect(ChroniqueDateHelper.expirationLabel(ChroniqueExpirationPreset.thirtyDays), '30 jours');
    final draft = ChroniqueScheduleDraft(
      publishMode: ChroniquePublishMode.schedule,
      scheduledAt: activation,
      expirationEnabled: true,
      expirationPreset: ChroniqueExpirationPreset.thirtyDays,
    );
    expect(draft.resolvedExpiresLocal(), DateTime(2026, 10, 24, 18, 30));
    expect(draft.validationError(now: DateTime(2026, 9, 20)), isNull);
  });
}
