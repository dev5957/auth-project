import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/features/chronique/models/chronique_schedule_draft.dart';
import 'package:mobile/features/chronique/models/media_draft.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_card.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_media_viewer.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_preview.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: const [LuminaColors.light]),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

MediaDraft _draft({
  required int id,
  required MediaDraftKind kind,
  String? fileName,
  int? byteSize,
  String? localPath,
}) {
  return MediaDraft(
    id: id,
    kind: kind,
    sourceType: MediaDraft.defaultSourceFor(kind),
    fileName: fileName,
    byteSize: byteSize,
    localPath: localPath,
  );
}

void main() {
  testWidgets('preview without media reuses the feed card', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ChroniquePreview(
          title: 'Titre',
          body: 'Le texte de la chronique, d au moins vingt caracteres.',
          medias: [],
          schedule: ChroniqueScheduleDraft(),
        ),
      ),
    );
    expect(find.byType(ChroniqueCard), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-card-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-feed-media-band')), findsNothing);
    expect(find.byKey(const ValueKey('chronique-share')), findsOneWidget);
  });

  testWidgets('preview omits title and keeps the compact header', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ChroniquePreview(
          title: '   ',
          body: 'Le texte de la chronique, d au moins vingt caracteres.',
          medias: [],
          schedule: ChroniqueScheduleDraft(),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('chronique-card-title')), findsNothing);
    expect(find.byType(ChroniqueCard), findsOneWidget);
  });

  testWidgets('preview folds a long body like the feed', (tester) async {
    final body = List.generate(12, (i) => 'Ligne $i du texte assez long pour dépasser.').join('\n');
    await tester.pumpWidget(
      _wrap(
        ChroniquePreview(
          title: 'Titre',
          body: body,
          medias: const [],
          schedule: const ChroniqueScheduleDraft(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Voir plus'), findsOneWidget);
    await tester.tap(find.text('Voir plus'));
    await tester.pump();
    expect(find.text('Voir moins'), findsOneWidget);
  });

  testWidgets('preview shows local image video audio and document tiles', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniquePreview(
          title: 'Médias',
          body: 'Le texte de la chronique, d au moins vingt caracteres.',
          medias: [
            _draft(id: 1, kind: MediaDraftKind.image, fileName: 'a.jpg', localPath: '/tmp/a.jpg'),
            _draft(id: 2, kind: MediaDraftKind.video, fileName: 'b.mp4', localPath: '/tmp/b.mp4'),
            _draft(id: 3, kind: MediaDraftKind.audio, fileName: 'c.m4a', localPath: '/tmp/c.m4a'),
            _draft(id: 4, kind: MediaDraftKind.document, fileName: 'd.pdf', byteSize: 2048),
          ],
          schedule: const ChroniqueScheduleDraft(),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('chronique-feed-media-band')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-feed-media-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-feed-media-2')), findsOneWidget);
    expect(find.text('Média indisponible'), findsNothing);
    expect(find.text('Vidéo'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle), findsWidgets);
    expect(find.byKey(const ValueKey('chronique-feed-media-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-feed-media-4')), findsOneWidget);
    expect(find.text('d.pdf'), findsOneWidget);
    expect(find.text('2 Ko'), findsOneWidget);
  });

  testWidgets('preview with five drafts uses two left heroes', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniquePreview(
          title: 'Cinq',
          body: 'Le texte de la chronique, d au moins vingt caracteres.',
          medias: [
            _draft(id: 1, kind: MediaDraftKind.image, fileName: 'a.jpg', localPath: '/tmp/a.jpg'),
            _draft(id: 2, kind: MediaDraftKind.image, fileName: 'b.jpg', localPath: '/tmp/b.jpg'),
            _draft(id: 3, kind: MediaDraftKind.video, fileName: 'c.mp4', localPath: '/tmp/c.mp4'),
            _draft(id: 4, kind: MediaDraftKind.video, fileName: 'd.mp4', localPath: '/tmp/d.mp4'),
            _draft(id: 5, kind: MediaDraftKind.audio, fileName: 'e.m4a', localPath: '/tmp/e.m4a'),
          ],
          schedule: const ChroniqueScheduleDraft(),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final first = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-1')));
    final second = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-2')));
    final third = tester.getRect(find.byKey(const ValueKey('chronique-feed-media-3')));
    expect(first.left, closeTo(second.left, 0.5));
    expect(first.top, lessThan(second.top));
    expect(first.left, lessThan(third.left));
    expect(find.text('e.m4a'), findsOneWidget);
  });

  testWidgets('preview audio tap opens a compact dialog', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniquePreview(
          title: 'Titre',
          body: 'Le texte de la chronique, d au moins vingt caracteres.',
          medias: [
            _draft(id: 3, kind: MediaDraftKind.audio, fileName: 'c.m4a', localPath: '/tmp/c.m4a'),
          ],
          schedule: const ChroniqueScheduleDraft(),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('chronique-feed-media-3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ChroniqueMediaViewerPage), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-viewer-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-viewer-audio')), findsOneWidget);
  });

  test('draft mapping keeps local files and sort order without remote urls', () {
    final medias = chroniquePreviewMediaFromDrafts([
      _draft(id: 9, kind: MediaDraftKind.document, fileName: 'z.pdf'),
      _draft(id: 8, kind: MediaDraftKind.image, fileName: 'a.jpg', localPath: '/tmp/a.jpg'),
    ]);
    expect(medias.map((item) => item.id).toList(), [9, 8]);
    expect(medias.every((item) => item.readUrl == null), isTrue);
    expect(chroniquePreviewLocalPaths([
      _draft(id: 8, kind: MediaDraftKind.image, localPath: '/tmp/a.jpg'),
    ])[8], '/tmp/a.jpg');
  });
}
