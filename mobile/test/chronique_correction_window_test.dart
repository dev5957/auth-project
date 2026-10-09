import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/models/chronique_correction_window.dart';

Chronique _active({required String publishedAt}) {
  return Chronique(
    id: 1,
    body: 'Le texte de la chronique, d au moins vingt caracteres.',
    status: 'active',
    publishedAt: publishedAt,
  );
}

void main() {
  final published = DateTime.utc(2026, 10, 8, 14);

  test('active correction is open before published_at + 30 minutes', () {
    expect(
      isChroniqueTextCorrectionOpen(
        _active(publishedAt: published.toIso8601String()),
        now: published.add(const Duration(minutes: 29, milliseconds: 999)),
      ),
      isTrue,
    );
  });

  test('active correction is closed at exactly published_at + 30:00.000', () {
    expect(
      isChroniqueTextCorrectionOpen(
        _active(publishedAt: published.toIso8601String()),
        now: published.add(kChroniqueCorrectionWindow),
      ),
      isFalse,
    );
  });

  test('active correction stays closed after 30 minutes', () {
    expect(
      isChroniqueTextCorrectionOpen(
        _active(publishedAt: published.toIso8601String()),
        now: published.add(const Duration(minutes: 31)),
      ),
      isFalse,
    );
  });

  test('scheduled with published_at null stays editable', () {
    expect(
      isChroniqueTextCorrectionOpen(
        Chronique(
          id: 2,
          body: 'Le texte de la chronique, d au moins vingt caracteres.',
          status: 'scheduled',
          scheduledAt: published.add(const Duration(hours: 2)),
        ),
        now: published.add(const Duration(minutes: 40)),
      ),
      isTrue,
    );
  });

  test('archived and expired are not in the correction window', () {
    expect(
      isChroniqueTextCorrectionOpen(
        _active(publishedAt: published.toIso8601String()).copyWith(status: 'archived'),
        now: published.add(const Duration(minutes: 5)),
      ),
      isFalse,
    );
    expect(
      isChroniqueTextCorrectionOpen(
        _active(publishedAt: published.toIso8601String()).copyWith(status: 'expired'),
        now: published.add(const Duration(minutes: 5)),
      ),
      isFalse,
    );
  });
}
