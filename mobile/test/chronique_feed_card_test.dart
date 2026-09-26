import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_card.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_feed_media.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_media_viewer.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_video_list.dart';

Widget _wrap(Widget child, {double width = 390}) {
  return MaterialApp(
    theme: ThemeData(extensions: const [LuminaColors.light]),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

ChroniqueMedia _media({
  required int id,
  required String kind,
  int sortOrder = 0,
  String? readUrl = 'https://example.test/file',
  DateTime? readExpiresAt,
  String? fileName,
  int? byteSize,
}) {
  return ChroniqueMedia(
    id: id,
    kind: kind,
    sortOrder: sortOrder,
    status: 'ready',
    contentType: kind == 'image' ? 'image/jpeg' : '$kind/test',
    originalFilename: fileName,
    byteSize: byteSize,
    readUrl: readUrl,
    readExpiresAt: readExpiresAt,
  );
}

Chronique _chronique({
  String? title = 'Titre',
  String body = 'Le texte de la chronique, d au moins vingt caracteres.',
  List<ChroniqueMedia> media = const [],
}) {
  return Chronique(
    id: 42,
    title: title,
    body: body,
    status: 'active',
    publishedAt: '2026-09-22T10:00:00.000Z',
    media: media,
  );
}

void main() {
  test('feed media band height scales from the 390 pt reference', () {
    expect(chroniqueFeedMediaBandHeight(count: 0, width: 390), 0);
    expect(chroniqueFeedMediaBandHeight(count: 1, width: 390), closeTo(390 * 9 / 16, 0.001));
    expect(chroniqueFeedMediaBandHeight(count: 2, width: 390), 219);
    expect(chroniqueFeedMediaBandHeight(count: 3, width: 390), 260);
    expect(chroniqueFeedMediaBandHeight(count: 4, width: 390), 310);
    expect(chroniqueFeedMediaBandHeight(count: 5, width: 390), 360);
    expect(chroniqueFeedMediaBandHeight(count: 2, width: 195), 109.5);
  });

  test('expired signed url is not treated as missing media', () {
    final expired = _media(
      id: 1,
      kind: 'image',
      readExpiresAt: DateTime.parse('2020-01-01T00:00:00.000Z'),
    );
    expect(chroniqueFeedReadUrlExpired(expired, DateTime.parse('2026-09-26T00:00:00.000Z')), isTrue);
    expect(chroniqueFeedHasUsableReadUrl(expired, DateTime.parse('2026-09-26T00:00:00.000Z')), isFalse);
    expect(chroniqueFeedMediaItems([expired]), hasLength(1));
  });

  testWidgets('card without media hides the media band', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueCard(
          chronique: _chronique(media: const []),
          showFeedMedia: true,
          showInactiveSocialActions: true,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('chronique-feed-media-band')), findsNothing);
    expect(find.byKey(const ValueKey('chronique-share')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-like')), findsOneWidget);
  });

  testWidgets('title can be omitted while keeping the menu header', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueCard(
          chronique: _chronique(title: null),
          showFeedMedia: true,
          onMenuSelected: (_) {},
        ),
      ),
    );
    expect(find.byKey(const ValueKey('chronique-card-title')), findsNothing);
    expect(find.byTooltip('Actions'), findsOneWidget);
  });

  testWidgets('long body collapses to six lines then expands', (tester) async {
    final body = List.generate(12, (i) => 'Ligne $i du texte assez long pour dépasser.').join('\n');
    await tester.pumpWidget(
      _wrap(
        ChroniqueCard(
          chronique: _chronique(body: body),
          showFeedMedia: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Voir plus'), findsOneWidget);
    final collapsed = tester.widget<Text>(find.byKey(const ValueKey('chronique-card-body')));
    expect(collapsed.maxLines, 6);
    await tester.tap(find.text('Voir plus'));
    await tester.pump();
    expect(find.text('Voir moins'), findsOneWidget);
    final expanded = tester.widget<Text>(find.byKey(const ValueKey('chronique-card-body')));
    expect(expanded.maxLines, isNull);
  });

  testWidgets('one to five media keep API order and expected tile count', (tester) async {
    for (var count = 1; count <= 5; count++) {
      final medias = [
        for (var i = 0; i < count; i++)
          _media(id: (count - i) * 10, kind: 'image', sortOrder: i, fileName: 'f$i.jpg'),
      ];
      await tester.pumpWidget(
        _wrap(
          ChroniqueCard(
            chronique: _chronique(media: medias),
            showFeedMedia: true,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('chronique-feed-media-band')), findsOneWidget);
      expect(find.byKey(ValueKey('chronique-feed-media-${count * 10}')), findsOneWidget);
      final band = tester.getSize(find.byKey(const ValueKey('chronique-feed-media-band')));
      expect(band.height, closeTo(chroniqueFeedMediaBandHeight(count: count, width: band.width), 0.5));
    }
  });

  testWidgets('two media sit side by side in API order', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueFeedMediaBand(
          medias: [
            _media(id: 2, kind: 'video', sortOrder: 1),
            _media(id: 1, kind: 'image', sortOrder: 0),
          ],
        ),
      ),
    );
    final left = tester.getTopLeft(find.byKey(const ValueKey('chronique-feed-media-1')));
    final right = tester.getTopLeft(find.byKey(const ValueKey('chronique-feed-media-2')));
    expect(left.dx, lessThan(right.dx));
  });

  testWidgets('expired image shows a fallback instead of disappearing', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueFeedMediaBand(
          medias: [
            _media(
              id: 7,
              kind: 'image',
              readExpiresAt: DateTime.parse('2020-01-01T00:00:00.000Z'),
            ),
          ],
        ),
      ),
    );
    expect(find.byKey(const ValueKey('chronique-feed-media-7')), findsOneWidget);
    expect(find.text('Lien expiré'), findsOneWidget);
  });

  testWidgets('tap on media opens the viewer, tap on title does not', (tester) async {
    var mediaTaps = 0;
    var copyTaps = 0;
    await tester.pumpWidget(
      _wrap(
        ChroniqueCard(
          chronique: _chronique(
            media: [_media(id: 4, kind: 'audio', fileName: 'voix.mp3')],
          ),
          showFeedMedia: true,
          onTap: () => copyTaps += 1,
          onMediaSelected: (_) => mediaTaps += 1,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('chronique-feed-media-4')));
    await tester.pump();
    expect(mediaTaps, 1);
    expect(copyTaps, 0);
    await tester.tap(find.byKey(const ValueKey('chronique-card-title')));
    await tester.pump();
    expect(copyTaps, 1);
    expect(mediaTaps, 1);
  });

  testWidgets('three media keep the first tile on the left', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueFeedMediaBand(
          medias: [
            _media(id: 1, kind: 'image', sortOrder: 0),
            _media(id: 2, kind: 'image', sortOrder: 1),
            _media(id: 3, kind: 'image', sortOrder: 2),
          ],
        ),
      ),
    );
    final first = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-1')));
    final second = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-2')));
    final third = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-3')));
    expect(first.left, lessThan(second.left));
    expect(second.left, closeTo(third.left, 0.5));
    expect(second.top, lessThan(third.top));
  });

  testWidgets('document tile shows name and size without inventing a preview', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueFeedMediaBand(
          medias: [
            _media(
              id: 9,
              kind: 'document',
              fileName: 'note.pdf',
              byteSize: 2048,
            ),
          ],
        ),
      ),
    );
    expect(find.text('note.pdf'), findsOneWidget);
    expect(find.text('2 Ko'), findsOneWidget);
  });

  testWidgets('unusable image url shows a neutral fallback', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueFeedMediaBand(
          medias: [
            _media(id: 12, kind: 'image', readUrl: ''),
          ],
        ),
      ),
    );
    expect(find.byKey(const ValueKey('chronique-feed-media-12')), findsOneWidget);
    expect(find.text('Média indisponible'), findsOneWidget);
  });

  testWidgets('voir plus does not open the chronique detail', (tester) async {
    var copyTaps = 0;
    final body = List.generate(12, (i) => 'Ligne $i du texte assez long pour dépasser.').join('\n');
    await tester.pumpWidget(
      _wrap(
        ChroniqueCard(
          chronique: _chronique(body: body),
          showFeedMedia: true,
          onTap: () => copyTaps += 1,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Voir plus'));
    await tester.pump();
    expect(copyTaps, 0);
    expect(find.text('Voir moins'), findsOneWidget);
  });

  testWidgets('media viewer reuses the ready video player', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [LuminaColors.light]),
        home: ChroniqueMediaViewerPage(
          media: _media(id: 8, kind: 'video', readUrl: 'https://example.test/clip.mp4'),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('chronique-media-viewer-video')), findsOneWidget);
    expect(find.byType(ChroniqueReadyVideoPlayer), findsOneWidget);
    expect(find.text('Vidéo'), findsWidgets);
  });
}
