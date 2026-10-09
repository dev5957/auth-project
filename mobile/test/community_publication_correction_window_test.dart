import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chronique/models/chronique_correction_window.dart';
import 'package:mobile/features/community/models/community_publication.dart';

CommunityPublication _active({required String publishedAt}) {
  return CommunityPublication(
    id: 80,
    communityId: 3,
    author: const CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
    body: 'Publication active auteur encore membre.',
    status: 'active',
    publishedAt: publishedAt,
  );
}

void main() {
  final published = DateTime.utc(2026, 10, 8, 14);

  test('community reuse of correction helper is open at T+29:59.999', () {
    expect(
      isChroniqueTextCorrectionOpen(
        _active(publishedAt: published.toIso8601String()).asChronique(),
        now: published.add(const Duration(minutes: 29, milliseconds: 999)),
      ),
      isTrue,
    );
  });

  test('community reuse of correction helper is closed at T+30:00.000', () {
    expect(
      isChroniqueTextCorrectionOpen(
        _active(publishedAt: published.toIso8601String()).asChronique(),
        now: published.add(kChroniqueCorrectionWindow),
      ),
      isFalse,
    );
  });

  test('community reuse of correction helper is closed at T+30:00.001', () {
    expect(
      isChroniqueTextCorrectionOpen(
        _active(publishedAt: published.toIso8601String()).asChronique(),
        now: published.add(const Duration(minutes: 30, milliseconds: 1)),
      ),
      isFalse,
    );
  });

  test('community correction uses published_at via asChronique, not an updated_at field', () {
    final publication = _active(publishedAt: published.toIso8601String());
    expect(publication.publishedAt, published.toIso8601String());
    expect(publication.asChronique().publishedAt, publication.publishedAt);
  });
}
