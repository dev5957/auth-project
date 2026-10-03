import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_image_list.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: const [LuminaColors.light]),
    home: Scaffold(body: child),
  );
}

void main() {
  test('ready image JSON maps readUrl without storage_key', () {
    final media = ChroniqueMedia.fromJson({
      'id': 10,
      'kind': 'image',
      'source_type': 'gallery',
      'content_type': 'image/jpeg',
      'byte_size': 12345,
      'original_filename': 'soir.jpg',
      'sort_order': 0,
      'status': 'ready',
      'created_at': '2026-09-25T10:01:00.000Z',
      'read_url': 'https://example.test/image.jpg',
      'read_expires_at': '2026-09-25T10:16:00.000Z',
    });
    expect(media.id, 10);
    expect(media.kind, 'image');
    expect(media.status, 'ready');
    expect(media.readUrl, 'https://example.test/image.jpg');
    expect(media.readExpiresAt, DateTime.parse('2026-09-25T10:16:00.000Z'));
    expect(media.sortOrder, 0);
    expect(chroniqueMediaIsDisplayableImage(media), isTrue);
  });

  test('ready image without read_url does not throw', () {
    final media = ChroniqueMedia.fromJson({
      'id': 11,
      'kind': 'image',
      'status': 'ready',
    });
    expect(media.readUrl, isNull);
    expect(media.readExpiresAt, isNull);
    expect(chroniqueMediaIsDisplayableImage(media), isFalse);
  });

  test('pending_upload is not displayable even with a url', () {
    final media = ChroniqueMedia.fromJson({
      'kind': 'image',
      'status': 'pending_upload',
      'read_url': 'https://example.test/pending.jpg',
    });
    expect(chroniqueMediaIsDisplayableImage(media), isFalse);
  });

  test('failed is not displayable even with a url', () {
    final media = ChroniqueMedia.fromJson({
      'kind': 'image',
      'status': 'failed',
      'read_url': 'https://example.test/failed.jpg',
    });
    expect(chroniqueMediaIsDisplayableImage(media), isFalse);
  });

  test('video is not treated as a displayable image', () {
    final media = ChroniqueMedia.fromJson({
      'kind': 'video',
      'status': 'ready',
      'read_url': 'https://example.test/clip.mp4',
    });
    expect(chroniqueMediaIsDisplayableImage(media), isFalse);
  });

  test('displayable images follow sort_order', () {
    final ordered = displayableChroniqueImages([
      ChroniqueMedia.fromJson({
        'id': 2,
        'kind': 'image',
        'status': 'ready',
        'sort_order': 2,
        'read_url': 'https://example.test/c.jpg',
      }),
      ChroniqueMedia.fromJson({
        'id': 1,
        'kind': 'image',
        'status': 'ready',
        'sort_order': 0,
        'read_url': 'https://example.test/a.jpg',
      }),
      ChroniqueMedia.fromJson({
        'id': 9,
        'kind': 'video',
        'status': 'ready',
        'sort_order': 1,
        'read_url': 'https://example.test/skip.mp4',
      }),
      ChroniqueMedia.fromJson({
        'id': 3,
        'kind': 'image',
        'status': 'ready',
        'sort_order': 1,
        'read_url': 'https://example.test/b.jpg',
      }),
    ]);
    expect(ordered.map((item) => item.readUrl).toList(), [
      'https://example.test/a.jpg',
      'https://example.test/b.jpg',
      'https://example.test/c.jpg',
    ]);
  });

  testWidgets('ready image uses Image.network without Authorization', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueReadyImageList(
          medias: [
            ChroniqueMedia.fromJson({
              'id': 10,
              'kind': 'image',
              'status': 'ready',
              'read_url': 'https://example.test/image.jpg',
            }),
          ],
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image;
    expect(provider, isA<NetworkImage>());
    expect((provider as NetworkImage).url, 'https://example.test/image.jpg');
    expect(provider.headers, isNull);
  });

  testWidgets('pending failed and video do not create Image.network', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueReadyImageList(
          medias: [
            ChroniqueMedia.fromJson({
              'kind': 'image',
              'status': 'pending_upload',
              'read_url': 'https://example.test/pending.jpg',
            }),
            ChroniqueMedia.fromJson({
              'kind': 'image',
              'status': 'failed',
              'read_url': 'https://example.test/failed.jpg',
            }),
            ChroniqueMedia.fromJson({
              'kind': 'video',
              'status': 'ready',
              'read_url': 'https://example.test/clip.mp4',
            }),
            ChroniqueMedia.fromJson({
              'kind': 'audio',
              'status': 'ready',
              'read_url': 'https://example.test/voix.mp3',
            }),
            ChroniqueMedia.fromJson({
              'kind': 'document',
              'status': 'ready',
              'read_url': 'https://example.test/note.pdf',
            }),
          ],
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('several ready images keep sort_order in the tree', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueReadyImageList(
          medias: [
            ChroniqueMedia.fromJson({
              'id': 2,
              'kind': 'image',
              'status': 'ready',
              'sort_order': 1,
              'read_url': 'https://example.test/second.jpg',
            }),
            ChroniqueMedia.fromJson({
              'id': 1,
              'kind': 'image',
              'status': 'ready',
              'sort_order': 0,
              'read_url': 'https://example.test/first.jpg',
            }),
          ],
        ),
      ),
    );
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(2));
    expect((images[0].image as NetworkImage).url, 'https://example.test/first.jpg');
    expect((images[1].image as NetworkImage).url, 'https://example.test/second.jpg');
  });
}
