import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_audio_list.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_document_list.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_image_list.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_remote_media_list.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_video_list.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: const [LuminaColors.light]),
    home: Scaffold(body: child),
  );
}

ChroniqueMedia _document({
  required int id,
  required int sortOrder,
  String? status = 'ready',
  String? readUrl = 'https://example.test/note.pdf',
  String? contentType,
  String? originalFilename,
}) {
  return ChroniqueMedia.fromJson({
    'id': id,
    'kind': 'document',
    'status': status,
    'sort_order': sortOrder,
    if (readUrl != null) 'read_url': readUrl,
    if (contentType != null) 'content_type': contentType,
    if (originalFilename != null) 'original_filename': originalFilename,
  });
}

ChroniqueMedia _image({
  required int id,
  required int sortOrder,
  String readUrl = 'https://example.test/image.jpg',
}) {
  return ChroniqueMedia.fromJson({
    'id': id,
    'kind': 'image',
    'status': 'ready',
    'sort_order': sortOrder,
    'read_url': readUrl,
  });
}

ChroniqueMedia _video({
  required int id,
  required int sortOrder,
  String readUrl = 'https://example.test/clip.mp4',
}) {
  return ChroniqueMedia.fromJson({
    'id': id,
    'kind': 'video',
    'status': 'ready',
    'sort_order': sortOrder,
    'read_url': readUrl,
  });
}

ChroniqueMedia _audio({
  required int id,
  required int sortOrder,
  String readUrl = 'https://example.test/voix.mp3',
}) {
  return ChroniqueMedia.fromJson({
    'id': id,
    'kind': 'audio',
    'status': 'ready',
    'sort_order': sortOrder,
    'read_url': readUrl,
  });
}

void main() {
  test('1 JSON document ready with read_url is parsed', () {
    final media = ChroniqueMedia.fromJson({
      'id': 7,
      'kind': 'document',
      'source_type': 'upload',
      'content_type': 'application/pdf',
      'status': 'ready',
      'sort_order': 0,
      'original_filename': 'note.pdf',
      'read_url': 'https://example.test/note.pdf',
      'read_expires_at': '2026-09-25T10:16:00.000Z',
    });
    expect(media.readUrl, 'https://example.test/note.pdf');
    expect(media.readExpiresAt, DateTime.parse('2026-09-25T10:16:00.000Z'));
    expect(media.contentType, 'application/pdf');
    expect(media.originalFilename, 'note.pdf');
    expect(chroniqueMediaIsDisplayableDocument(media), isTrue);
  });

  test('2 pending_upload document is ignored', () {
    expect(
      chroniqueMediaIsDisplayableDocument(
        _document(id: 1, sortOrder: 0, status: 'pending_upload'),
      ),
      isFalse,
    );
  });

  test('3 failed document is ignored', () {
    expect(
      chroniqueMediaIsDisplayableDocument(_document(id: 1, sortOrder: 0, status: 'failed')),
      isFalse,
    );
  });

  test('4 ready document without read_url is ignored', () {
    final media = ChroniqueMedia.fromJson({
      'id': 2,
      'kind': 'document',
      'status': 'ready',
      'content_type': 'application/pdf',
    });
    expect(media.readUrl, isNull);
    expect(chroniqueMediaIsDisplayableDocument(media), isFalse);
  });

  test('5 only document ready with non-empty readUrl is displayable', () {
    expect(
      chroniqueMediaIsDisplayableDocument(
        _document(id: 1, sortOrder: 0, readUrl: 'https://example.test/note.pdf'),
      ),
      isTrue,
    );
  });

  test('6-9 short type from content_type', () {
    expect(
      chroniqueDocumentShortType(_document(id: 1, sortOrder: 0, contentType: 'application/pdf')),
      'PDF',
    );
    expect(
      chroniqueDocumentShortType(_document(id: 2, sortOrder: 0, contentType: 'application/msword')),
      'DOC',
    );
    expect(
      chroniqueDocumentShortType(
        _document(
          id: 3,
          sortOrder: 0,
          contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ),
      ),
      'DOCX',
    );
    expect(
      chroniqueDocumentShortType(_document(id: 4, sortOrder: 0, contentType: 'text/plain')),
      'TXT',
    );
  });

  test('10 short type fallback from original_filename extension', () {
    expect(
      chroniqueDocumentShortType(_document(id: 1, sortOrder: 0, originalFilename: 'a.PDF')),
      'PDF',
    );
    expect(
      chroniqueDocumentShortType(_document(id: 2, sortOrder: 0, originalFilename: 'b.doc')),
      'DOC',
    );
    expect(
      chroniqueDocumentShortType(_document(id: 3, sortOrder: 0, originalFilename: 'c.docx')),
      'DOCX',
    );
    expect(
      chroniqueDocumentShortType(_document(id: 4, sortOrder: 0, originalFilename: 'd.txt')),
      'TXT',
    );
  });

  test('11-12 display name uses original filename or Document', () {
    expect(
      chroniqueDocumentDisplayName(_document(id: 1, sortOrder: 0, originalFilename: 'contrat.pdf')),
      'contrat.pdf',
    );
    expect(chroniqueDocumentDisplayName(_document(id: 2, sortOrder: 0)), 'Document');
    expect(
      chroniqueDocumentDisplayName(_document(id: 3, sortOrder: 0, originalFilename: '  ')),
      'Document',
    );
  });

  test('16 image video audio are not documents', () {
    expect(chroniqueMediaIsDisplayableDocument(_image(id: 1, sortOrder: 0)), isFalse);
    expect(chroniqueMediaIsDisplayableDocument(_video(id: 2, sortOrder: 1)), isFalse);
    expect(chroniqueMediaIsDisplayableDocument(_audio(id: 3, sortOrder: 2)), isFalse);
    expect(chroniqueMediaIsDisplayableImage(_document(id: 4, sortOrder: 3)), isFalse);
    expect(chroniqueMediaIsDisplayableVideo(_document(id: 4, sortOrder: 3)), isFalse);
    expect(chroniqueMediaIsDisplayableAudio(_document(id: 4, sortOrder: 3)), isFalse);
  });

  testWidgets('13-14 card receives exact readUrl without Authorization', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueReadyDocumentList(
          medias: [
            _document(
              id: 8,
              sortOrder: 0,
              readUrl: 'https://example.test/note.pdf',
              originalFilename: 'note.pdf',
            ),
          ],
        ),
      ),
    );
    final card = tester.widget<ChroniqueReadyDocumentCard>(find.byType(ChroniqueReadyDocumentCard));
    expect(card.url, 'https://example.test/note.pdf');
    expect(card.url.contains('Authorization'), isFalse);
    expect(card.url.toLowerCase().contains('bearer'), isFalse);
    expect(find.text('note.pdf'), findsOneWidget);
    expect(find.text('Ouvrir'), findsOneWidget);
  });

  testWidgets('pending failed image do not create a document card', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueReadyDocumentList(
          medias: [
            _document(id: 1, sortOrder: 0, status: 'pending_upload'),
            _document(id: 2, sortOrder: 1, status: 'failed'),
            _image(id: 3, sortOrder: 2),
            _audio(id: 4, sortOrder: 3),
          ],
        ),
      ),
    );
    expect(find.byType(ChroniqueReadyDocumentCard), findsNothing);
  });

  test('15 several documents follow sort_order', () {
    final ordered = displayableChroniqueDocuments([
      _document(id: 3, sortOrder: 2, readUrl: 'https://example.test/c.txt', originalFilename: 'c.txt'),
      _document(id: 1, sortOrder: 0, readUrl: 'https://example.test/a.pdf', originalFilename: 'a.pdf'),
      _document(id: 2, sortOrder: 1, readUrl: 'https://example.test/b.docx', originalFilename: 'b.docx'),
    ]);
    expect(ordered.map((item) => item.readUrl).toList(), [
      'https://example.test/a.pdf',
      'https://example.test/b.docx',
      'https://example.test/c.txt',
    ]);
  });

  test('17 mix image document audio document video keeps global sort_order', () {
    final mixed = displayableChroniqueRemoteMedia([
      _video(id: 5, sortOrder: 4, readUrl: 'https://example.test/clip.mp4'),
      _document(
        id: 4,
        sortOrder: 3,
        readUrl: 'https://example.test/letter.docx',
        contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        originalFilename: 'letter.docx',
      ),
      _audio(id: 3, sortOrder: 2, readUrl: 'https://example.test/voix.mp3'),
      _document(
        id: 2,
        sortOrder: 1,
        readUrl: 'https://example.test/brief.pdf',
        contentType: 'application/pdf',
        originalFilename: 'brief.pdf',
      ),
      _image(id: 1, sortOrder: 0, readUrl: 'https://example.test/first.jpg'),
    ]);
    expect(mixed.map((item) => item.kind).toList(), ['image', 'document', 'audio', 'document', 'video']);
    expect(mixed.map((item) => item.readUrl).toList(), [
      'https://example.test/first.jpg',
      'https://example.test/brief.pdf',
      'https://example.test/voix.mp3',
      'https://example.test/letter.docx',
      'https://example.test/clip.mp4',
    ]);
  });

  testWidgets('17-18 mix builds image document audio document video, never audio for documents', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueReadyRemoteMediaList(
          medias: [
            _image(id: 1, sortOrder: 0, readUrl: 'https://example.test/first.jpg'),
            _document(
              id: 2,
              sortOrder: 1,
              readUrl: 'https://example.test/brief.pdf',
              contentType: 'application/pdf',
              originalFilename: 'brief.pdf',
            ),
            _audio(id: 3, sortOrder: 2, readUrl: 'https://example.test/voix.mp3'),
            _document(
              id: 4,
              sortOrder: 3,
              readUrl: 'https://example.test/letter.docx',
              contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
              originalFilename: 'letter.docx',
            ),
            _video(id: 5, sortOrder: 4, readUrl: 'https://example.test/clip.mp4'),
          ],
        ),
      ),
    );
    final cards = tester.widgetList<ChroniqueReadyDocumentCard>(find.byType(ChroniqueReadyDocumentCard)).toList();
    expect(cards, hasLength(2));
    expect(cards[0].url, 'https://example.test/brief.pdf');
    expect(cards[1].url, 'https://example.test/letter.docx');
    expect(find.byType(ChroniqueReadyAudioPlayer), findsOneWidget);
    expect(tester.widget<ChroniqueReadyAudioPlayer>(find.byType(ChroniqueReadyAudioPlayer)).url, 'https://example.test/voix.mp3');
    expect(find.byType(ChroniqueReadyVideoPlayer), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('DOCX'), findsOneWidget);

    expect(tester.getTopLeft(find.byType(Image)).dy < tester.getTopLeft(find.byType(ChroniqueReadyDocumentCard).first).dy, isTrue);
    expect(
      tester.getTopLeft(find.byType(ChroniqueReadyDocumentCard).first).dy <
          tester.getTopLeft(find.byType(ChroniqueReadyAudioPlayer)).dy,
      isTrue,
    );
    expect(
      tester.getTopLeft(find.byType(ChroniqueReadyAudioPlayer)).dy <
          tester.getTopLeft(find.byType(ChroniqueReadyDocumentCard).last).dy,
      isTrue,
    );
    expect(
      tester.getTopLeft(find.byType(ChroniqueReadyDocumentCard).last).dy <
          tester.getTopLeft(find.byType(ChroniqueReadyVideoPlayer)).dy,
      isTrue,
    );
  });

  testWidgets('19 open uses injected opener with exact readUrl Uri', (tester) async {
    Uri? opened;
    await tester.pumpWidget(
      _wrap(
        ChroniqueReadyDocumentList(
          medias: [
            _document(
              id: 1,
              sortOrder: 0,
              readUrl: 'https://example.test/note.pdf',
              originalFilename: 'note.pdf',
            ),
          ],
          openDocument: (uri) async {
            opened = uri;
            return true;
          },
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pump();
    expect(opened, Uri.parse('https://example.test/note.pdf'));
    expect(find.text(kChroniqueDocumentOpenFailedMessage), findsNothing);
  });

  testWidgets('20 launchUrl false shows message without crash', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueReadyDocumentList(
          medias: [_document(id: 1, sortOrder: 0, originalFilename: 'note.pdf')],
          openDocument: (_) async => false,
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pump();
    expect(find.text(kChroniqueDocumentOpenFailedMessage), findsOneWidget);
  });

  testWidgets('20 launchUrl throw shows message without crash', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueReadyDocumentList(
          medias: [_document(id: 1, sortOrder: 0, originalFilename: 'note.pdf')],
          openDocument: (_) async => throw Exception('blocked'),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pump();
    expect(find.text(kChroniqueDocumentOpenFailedMessage), findsOneWidget);
  });
}
