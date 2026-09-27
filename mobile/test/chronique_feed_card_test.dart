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

  testWidgets('four media keep a single left hero and three stacked right tiles', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueFeedMediaBand(
          medias: [
            for (var i = 1; i <= 4; i++)
              _media(id: i, kind: 'image', sortOrder: i - 1),
          ],
        ),
      ),
    );
    final band = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-band')));
    final first = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-1')));
    final second = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-2')));
    final third = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-3')));
    final fourth = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-4')));
    expect(first.left, lessThan(second.left));
    expect(second.left, closeTo(third.left, 0.5));
    expect(third.left, closeTo(fourth.left, 0.5));
    expect(second.top, lessThan(third.top));
    expect(third.top, lessThan(fourth.top));
    expect(first.height, closeTo(band.height, 1));
    expect(second.height, lessThan(first.height));
  });

  testWidgets('five media use two left heroes and three stacked right tiles', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueFeedMediaBand(
          medias: [
            for (var i = 1; i <= 5; i++)
              _media(id: i, kind: 'image', sortOrder: i - 1),
          ],
        ),
      ),
    );
    final first = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-1')));
    final second = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-2')));
    final third = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-3')));
    final fourth = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-4')));
    final fifth = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-5')));
    expect(first.left, closeTo(second.left, 0.5));
    expect(first.top, lessThan(second.top));
    expect(first.left, lessThan(third.left));
    expect(third.left, closeTo(fourth.left, 0.5));
    expect(fourth.left, closeTo(fifth.left, 0.5));
    expect(third.top, lessThan(fourth.top));
    expect(fourth.top, lessThan(fifth.top));
    expect(first.height, closeTo(second.height, 1));
    expect(third.height, closeTo(fourth.height, 1));
    expect(first.height, greaterThan(third.height));
  });

  testWidgets('mixed four and five media mosaics do not overflow', (tester) async {
    Future<void> pumpBand(List<ChroniqueMedia> medias, {double width = 390}) async {
      await tester.pumpWidget(_wrap(ChroniqueFeedMediaBand(medias: medias), width: width));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('chronique-feed-media-band')), findsOneWidget);
    }

    await pumpBand([
      _media(id: 1, kind: 'image', sortOrder: 0),
      _media(id: 2, kind: 'image', sortOrder: 1),
      _media(id: 3, kind: 'video', sortOrder: 2, fileName: 'a.mp4'),
      _media(id: 4, kind: 'video', sortOrder: 3, fileName: 'b.mp4'),
    ]);
    expect(find.text('Vidéo'), findsWidgets);

    await pumpBand([
      _media(id: 1, kind: 'image', sortOrder: 0),
      _media(id: 2, kind: 'image', sortOrder: 1),
      _media(id: 3, kind: 'video', sortOrder: 2, fileName: 'a.mp4'),
      _media(id: 4, kind: 'video', sortOrder: 3, fileName: 'b.mp4'),
      _media(id: 5, kind: 'audio', sortOrder: 4, fileName: 'voix.mp3'),
    ]);
    expect(find.text('voix.mp3'), findsOneWidget);

    await pumpBand([
      _media(id: 1, kind: 'image', sortOrder: 0),
      _media(id: 2, kind: 'image', sortOrder: 1),
      _media(id: 3, kind: 'video', sortOrder: 2, fileName: 'a.mp4'),
      _media(id: 4, kind: 'video', sortOrder: 3, fileName: 'b.mp4'),
      _media(id: 5, kind: 'document', sortOrder: 4, fileName: 'note.pdf', byteSize: 2048),
    ]);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);

    await pumpBand([
      _media(id: 1, kind: 'image', sortOrder: 0),
      _media(id: 2, kind: 'image', sortOrder: 1),
      _media(id: 3, kind: 'video', sortOrder: 2, fileName: 'a.mp4'),
      _media(id: 4, kind: 'video', sortOrder: 3, fileName: 'b.mp4'),
      _media(id: 5, kind: 'audio', sortOrder: 4, fileName: 'voix.mp3'),
    ], width: 294);
    expect(find.byKey(const ValueKey('chronique-feed-media-5')), findsOneWidget);
  });

  testWidgets('five media mosaic stays within a narrow phone band', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueFeedMediaBand(
          medias: [
            _media(id: 1, kind: 'image', sortOrder: 0),
            _media(id: 2, kind: 'video', sortOrder: 1, fileName: 'clip.mp4'),
            _media(id: 3, kind: 'video', sortOrder: 2, fileName: 'other.mp4'),
            _media(
              id: 4,
              kind: 'document',
              sortOrder: 3,
              fileName: 'compte-rendu-assemblee-generale-annuelle-tres-long.pdf',
              byteSize: 2048,
            ),
            _media(id: 5, kind: 'audio', sortOrder: 4, fileName: 'voix.mp3'),
          ],
        ),
        width: 294,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final band = tester.getSize(find.byKey(const ValueKey('chronique-feed-media-band')));
    expect(band.width, 294);
    expect(band.height, closeTo(chroniqueFeedMediaBandHeight(count: 5, width: 294), 0.5));
    expect(find.byIcon(Icons.play_circle), findsWidgets);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
  });

  testWidgets('five media mosaic with large text scale does not overflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [LuminaColors.light]),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          );
        },
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 294,
              child: ChroniqueFeedMediaBand(
                medias: [
                  ChroniqueMedia(
                    id: 1,
                    kind: 'image',
                    sortOrder: 0,
                    status: 'ready',
                    readUrl: 'https://example.test/file',
                  ),
                  ChroniqueMedia(
                    id: 2,
                    kind: 'image',
                    sortOrder: 1,
                    status: 'ready',
                    readUrl: 'https://example.test/file',
                  ),
                  ChroniqueMedia(
                    id: 3,
                    kind: 'video',
                    sortOrder: 2,
                    status: 'ready',
                    originalFilename: 'a.mp4',
                    readUrl: 'https://example.test/file',
                  ),
                  ChroniqueMedia(
                    id: 4,
                    kind: 'video',
                    sortOrder: 3,
                    status: 'ready',
                    originalFilename: 'b.mp4',
                    readUrl: 'https://example.test/file',
                  ),
                  ChroniqueMedia(
                    id: 5,
                    kind: 'document',
                    sortOrder: 4,
                    status: 'ready',
                    originalFilename: 'compte-rendu-assemblee-generale-annuelle-tres-long.pdf',
                    byteSize: 4096,
                    readUrl: 'https://example.test/file',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
  });

  testWidgets('tapping the fifth mosaic tile selects that media', (tester) async {
    ChroniqueMedia? selected;
    await tester.pumpWidget(
      _wrap(
        ChroniqueFeedMediaBand(
          medias: [
            _media(id: 1, kind: 'image', sortOrder: 0),
            _media(id: 2, kind: 'image', sortOrder: 1),
            _media(id: 3, kind: 'video', sortOrder: 2),
            _media(id: 4, kind: 'video', sortOrder: 3),
            _media(id: 5, kind: 'audio', sortOrder: 4, fileName: 'voix.mp3'),
          ],
          onSelect: (media) => selected = media,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('chronique-feed-media-5')));
    await tester.pump();
    expect(selected?.id, 5);
    expect(selected?.kind, 'audio');
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
    expect(find.byKey(const ValueKey('chronique-media-viewer-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-viewer-video')), findsOneWidget);
    expect(find.byType(ChroniqueReadyVideoPlayer), findsOneWidget);
    expect(find.text('Vidéo'), findsWidgets);
  });

  testWidgets('audio tile fills the cell with a mini player chrome', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueFeedMediaBand(
          medias: [
            _media(id: 4, kind: 'audio', fileName: 'voix.mp3'),
          ],
        ),
      ),
    );
    expect(find.byKey(const ValueKey('chronique-feed-media-4')), findsOneWidget);
    expect(find.text('voix.mp3'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
  });

  testWidgets('local video tile shows chrome instead of unavailable', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ChroniqueFeedMediaBand(
          medias: [
            ChroniqueMedia(
              id: 5,
              kind: 'video',
              status: 'ready',
              originalFilename: 'clip.mp4',
              sortOrder: 0,
            ),
          ],
          localPaths: {5: '/tmp/clip.mp4'},
        ),
      ),
    );
    expect(find.text('Média indisponible'), findsNothing);
    expect(find.text('Vidéo'), findsOneWidget);
    expect(find.text('clip.mp4'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle), findsOneWidget);
  });

  testWidgets('document and audio dialogs stay compact', (tester) async {
    Future<void> openKind(ChroniqueMedia media) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [LuminaColors.light]),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () => openChroniqueFeedMedia(context, media),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    await openKind(_media(id: 8, kind: 'audio', readUrl: 'https://example.test/clip.m4a'));
    expect(find.byKey(const ValueKey('chronique-media-viewer-audio')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('chronique-media-viewer-sheet'))).height,
      lessThan(tester.getSize(find.byType(Scaffold)).height * 0.5),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await openKind(_media(id: 9, kind: 'document', fileName: 'note.pdf', byteSize: 2048));
    expect(find.byKey(const ValueKey('chronique-media-viewer-document')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('chronique-media-viewer-sheet'))).height,
      lessThan(tester.getSize(find.byType(Scaffold)).height * 0.5),
    );
  });

  test('portrait video surface shrinks to the available height', () {
    final size = chroniqueVideoSurfaceSize(
      aspectRatio: 9 / 16,
      maxWidth: 320,
      maxHeight: 200,
    );
    expect(size.height, 200);
    expect(size.width, closeTo(200 * 9 / 16, 0.001));
    expect(size.width, lessThan(320));
  });

  test('landscape video keeps width when height allows', () {
    final size = chroniqueVideoSurfaceSize(
      aspectRatio: 16 / 9,
      maxWidth: 320,
      maxHeight: 400,
    );
    expect(size.width, 320);
    expect(size.height, closeTo(320 * 9 / 16, 0.001));
  });

  test('video surface uses 16:9 when the ratio is invalid', () {
    final size = chroniqueVideoSurfaceSize(
      aspectRatio: 0,
      maxWidth: 320,
      maxHeight: 400,
    );
    expect(size.width, 320);
    expect(size.height, closeTo(320 * 9 / 16, 0.001));
  });

  testWidgets('document dialog does not overflow on a short phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [LuminaColors.light]),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => openChroniqueFeedMedia(
                  context,
                  _media(
                    id: 9,
                    kind: 'document',
                    fileName: 'compte-rendu-assemblee-generale-annuelle-tres-long.pdf',
                    byteSize: 2048,
                  ),
                ),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('chronique-media-viewer-document')), findsOneWidget);
    expect(find.text('Ouvrir'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('chronique-media-viewer-sheet'))).height,
      lessThan(640 * 0.5),
    );
  });

  testWidgets('video dialog stays within a short phone without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [LuminaColors.light]),
        home: const ChroniqueMediaViewerPage(
          media: ChroniqueMedia(
            id: 8,
            kind: 'video',
            status: 'ready',
            readUrl: 'https://example.test/clip.mp4',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('chronique-media-viewer-video')), findsOneWidget);
    expect(find.byType(ChroniqueReadyVideoPlayer), findsOneWidget);
    final sheet = tester.getSize(find.byKey(const ValueKey('chronique-media-viewer-sheet')));
    expect(sheet.height, lessThanOrEqualTo(640 * 0.78 + 1));
  });

  test('keepExistingMedia retains previous media when the PATCH payload omits them', () {
    const previous = Chronique(
      id: 1,
      body: 'Le texte de la chronique, d au moins vingt caracteres.',
      status: 'active',
      media: [
        ChroniqueMedia(id: 10, kind: 'image', status: 'ready', sortOrder: 0),
      ],
    );
    const updated = Chronique(
      id: 1,
      title: 'Nouveau',
      body: 'Texte modifié d au moins vingt caracteres.',
      status: 'active',
    );
    final merged = Chronique.keepExistingMedia(previous, updated);
    expect(merged.id, 1);
    expect(merged.title, 'Nouveau');
    expect(merged.media, hasLength(1));
    expect(merged.media.single.id, 10);
  });

  test('keepExistingMedia uses a non-empty media list from the same chronique', () {
    const previous = Chronique(
      id: 1,
      body: 'Le texte de la chronique, d au moins vingt caracteres.',
      status: 'active',
      media: [
        ChroniqueMedia(id: 10, kind: 'image', status: 'ready', sortOrder: 0),
      ],
    );
    const updated = Chronique(
      id: 1,
      title: 'Nouveau',
      body: 'Texte modifié d au moins vingt caracteres.',
      status: 'active',
      media: [
        ChroniqueMedia(id: 20, kind: 'video', status: 'ready', sortOrder: 0),
      ],
    );
    final merged = Chronique.keepExistingMedia(previous, updated);
    expect(merged.media, hasLength(1));
    expect(merged.media.single.id, 20);
  });

  test('keepExistingMedia does not mix media from different chronique ids', () {
    const previous = Chronique(
      id: 1,
      body: 'Le texte de la chronique, d au moins vingt caracteres.',
      status: 'active',
      media: [
        ChroniqueMedia(id: 10, kind: 'image', status: 'ready', sortOrder: 0),
      ],
    );
    const updated = Chronique(
      id: 2,
      title: 'Autre',
      body: 'Texte d une autre chronique d au moins vingt caracteres.',
      status: 'active',
    );
    final merged = Chronique.keepExistingMedia(previous, updated);
    expect(merged.id, 2);
    expect(merged.title, 'Autre');
    expect(merged.media, isEmpty);
  });
}
