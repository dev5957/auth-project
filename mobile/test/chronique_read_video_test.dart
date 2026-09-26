import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_image_list.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_remote_media_list.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_video_list.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: const [LuminaColors.light]),
    home: Scaffold(body: child),
  );
}

ChroniqueMedia _video({
  required int id,
  required int sortOrder,
  String? status = 'ready',
  String? readUrl = 'https://example.test/clip.mp4',
}) {
  return ChroniqueMedia.fromJson({
    'id': id,
    'kind': 'video',
    'status': status,
    'sort_order': sortOrder,
    if (readUrl != null) 'read_url': readUrl,
  });
}

void main() {
  test('A video ready with read_url is displayable', () {
    final media = ChroniqueMedia.fromJson({
      'id': 4,
      'kind': 'video',
      'source_type': 'gallery',
      'content_type': 'video/mp4',
      'status': 'ready',
      'sort_order': 0,
      'read_url': 'https://example.test/clip.mp4',
      'read_expires_at': '2026-09-25T10:16:00.000Z',
    });
    expect(media.readUrl, 'https://example.test/clip.mp4');
    expect(media.readExpiresAt, DateTime.parse('2026-09-25T10:16:00.000Z'));
    expect(chroniqueMediaIsDisplayableVideo(media), isTrue);
  });

  test('B video ready without read_url is not displayable', () {
    final media = ChroniqueMedia.fromJson({
      'id': 5,
      'kind': 'video',
      'status': 'ready',
    });
    expect(media.readUrl, isNull);
    expect(chroniqueMediaIsDisplayableVideo(media), isFalse);
  });

  test('C pending_upload video is not displayable even with a url', () {
    expect(
      chroniqueMediaIsDisplayableVideo(
        _video(id: 1, sortOrder: 0, status: 'pending_upload'),
      ),
      isFalse,
    );
  });

  test('D failed video is not displayable even with a url', () {
    expect(
      chroniqueMediaIsDisplayableVideo(_video(id: 1, sortOrder: 0, status: 'failed')),
      isFalse,
    );
  });

  test('E image is not taken by the video widget filter', () {
    final image = ChroniqueMedia.fromJson({
      'kind': 'image',
      'status': 'ready',
      'read_url': 'https://example.test/image.jpg',
    });
    expect(chroniqueMediaIsDisplayableVideo(image), isFalse);
    expect(chroniqueMediaIsDisplayableImage(image), isTrue);
  });

  test('F several videos follow sort_order', () {
    final ordered = displayableChroniqueVideos([
      _video(id: 3, sortOrder: 2, readUrl: 'https://example.test/c.mp4'),
      _video(id: 1, sortOrder: 0, readUrl: 'https://example.test/a.mp4'),
      _video(id: 2, sortOrder: 1, readUrl: 'https://example.test/b.mp4'),
    ]);
    expect(ordered.map((item) => item.readUrl).toList(), [
      'https://example.test/a.mp4',
      'https://example.test/b.mp4',
      'https://example.test/c.mp4',
    ]);
  });

  testWidgets('G/H player widget receives exact readUrl and no Authorization', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueReadyVideoList(
          medias: [_video(id: 8, sortOrder: 0, readUrl: 'https://example.test/clip.mp4')],
        ),
      ),
    );
    final player = tester.widget<ChroniqueReadyVideoPlayer>(find.byType(ChroniqueReadyVideoPlayer));
    expect(player.url, 'https://example.test/clip.mp4');
    expect(player.url.contains('Authorization'), isFalse);
    expect(player.url.toLowerCase().contains('bearer'), isFalse);
  });

  testWidgets('pending failed and image do not create a video player', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueReadyVideoList(
          medias: [
            _video(id: 1, sortOrder: 0, status: 'pending_upload'),
            _video(id: 2, sortOrder: 1, status: 'failed'),
            ChroniqueMedia.fromJson({
              'id': 3,
              'kind': 'image',
              'status': 'ready',
              'read_url': 'https://example.test/image.jpg',
            }),
          ],
        ),
      ),
    );
    expect(find.byType(ChroniqueReadyVideoPlayer), findsNothing);
  });

  test('I mixed image and video keep global sort_order', () {
    final mixed = displayableChroniqueRemoteMedia([
      ChroniqueMedia.fromJson({
        'id': 2,
        'kind': 'video',
        'status': 'ready',
        'sort_order': 1,
        'read_url': 'https://example.test/mid.mp4',
      }),
      ChroniqueMedia.fromJson({
        'id': 3,
        'kind': 'image',
        'status': 'ready',
        'sort_order': 2,
        'read_url': 'https://example.test/last.jpg',
      }),
      ChroniqueMedia.fromJson({
        'id': 1,
        'kind': 'image',
        'status': 'ready',
        'sort_order': 0,
        'read_url': 'https://example.test/first.jpg',
      }),
    ]);
    expect(mixed.map((item) => item.kind).toList(), ['image', 'video', 'image']);
    expect(mixed.map((item) => item.readUrl).toList(), [
      'https://example.test/first.jpg',
      'https://example.test/mid.mp4',
      'https://example.test/last.jpg',
    ]);
  });

  testWidgets('I mixed list builds image then video then image', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueReadyRemoteMediaList(
          medias: [
            ChroniqueMedia.fromJson({
              'id': 1,
              'kind': 'image',
              'status': 'ready',
              'sort_order': 0,
              'read_url': 'https://example.test/first.jpg',
            }),
            _video(id: 2, sortOrder: 1, readUrl: 'https://example.test/mid.mp4'),
            ChroniqueMedia.fromJson({
              'id': 3,
              'kind': 'image',
              'status': 'ready',
              'sort_order': 2,
              'read_url': 'https://example.test/last.jpg',
            }),
          ],
        ),
      ),
    );
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(2));
    expect((images[0].image as NetworkImage).url, 'https://example.test/first.jpg');
    expect((images[1].image as NetworkImage).url, 'https://example.test/last.jpg');
    final player = tester.widget<ChroniqueReadyVideoPlayer>(find.byType(ChroniqueReadyVideoPlayer));
    expect(player.url, 'https://example.test/mid.mp4');
    expect((images[0].image as NetworkImage).headers, isNull);

    final imageFinder = find.byType(Image);
    final videoFinder = find.byType(ChroniqueReadyVideoPlayer);
    expect(tester.getTopLeft(imageFinder.first).dy < tester.getTopLeft(videoFinder).dy, isTrue);
    expect(tester.getTopLeft(videoFinder).dy < tester.getTopLeft(imageFinder.last).dy, isTrue);
  });

  test('clock format is MM:SS under one hour and HH:MM:SS after', () {
    expect(formatChroniqueVideoClock(Duration.zero), '00:00');
    expect(formatChroniqueVideoClock(const Duration(seconds: 5)), '00:05');
    expect(formatChroniqueVideoClock(const Duration(minutes: 3, seconds: 7)), '03:07');
    expect(formatChroniqueVideoClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '01:02:03');
  });

  test('pause icon follows real controller state including natural end', () {
    const playing = VideoPlayerValue(
      duration: Duration(seconds: 10),
      position: Duration(seconds: 4),
      isInitialized: true,
      isPlaying: true,
    );
    const paused = VideoPlayerValue(
      duration: Duration(seconds: 10),
      position: Duration(seconds: 4),
      isInitialized: true,
    );
    const endedWhileFlagStillPlaying = VideoPlayerValue(
      duration: Duration(seconds: 10),
      position: Duration(seconds: 10),
      isInitialized: true,
      isPlaying: true,
    );
    const completed = VideoPlayerValue(
      duration: Duration(seconds: 10),
      position: Duration(seconds: 10),
      isInitialized: true,
      isCompleted: true,
    );
    const seekToEndPaused = VideoPlayerValue(
      duration: Duration(seconds: 10),
      position: Duration(seconds: 10),
      isInitialized: true,
    );
    expect(chroniqueVideoShowsPauseIcon(playing), isTrue);
    expect(chroniqueVideoShowsPauseIcon(paused), isFalse);
    expect(chroniqueVideoShowsPauseIcon(endedWhileFlagStillPlaying), isFalse);
    expect(chroniqueVideoShowsPauseIcon(completed), isFalse);
    expect(chroniqueVideoShowsPauseIcon(seekToEndPaused), isFalse);
    expect(chroniqueVideoIsAtEnd(endedWhileFlagStillPlaying), isTrue);
    expect(chroniqueVideoIsAtEnd(completed), isTrue);
    expect(chroniqueVideoIsAtEnd(playing), isFalse);
  });

  test('slider value and seek target stay within duration without network', () {
    const duration = Duration(seconds: 10);
    expect(
      chroniqueVideoSliderValue(position: const Duration(seconds: 4), duration: duration),
      4000,
    );
    expect(
      chroniqueVideoSliderValue(
        position: const Duration(seconds: 4),
        duration: duration,
        scrubMilliseconds: 7500,
      ),
      7500,
    );
    expect(
      chroniqueVideoSliderValue(position: const Duration(seconds: 20), duration: duration),
      10000,
    );
    expect(chroniqueVideoSeekTarget(duration: duration, milliseconds: 2500), const Duration(milliseconds: 2500));
    expect(chroniqueVideoSeekTarget(duration: duration, milliseconds: 10000), duration);
    expect(chroniqueVideoSeekTarget(duration: duration, milliseconds: -5), Duration.zero);
    expect(chroniqueVideoSeekTarget(duration: Duration.zero, milliseconds: 100), Duration.zero);
  });
}
