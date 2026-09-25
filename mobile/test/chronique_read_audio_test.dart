import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_audio_list.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_image_list.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_remote_media_list.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_video_list.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: const [LuminaColors.light]),
    home: Scaffold(body: child),
  );
}

ChroniqueMedia _audio({
  required int id,
  required int sortOrder,
  String? status = 'ready',
  String? readUrl = 'https://example.test/voix.mp3',
}) {
  return ChroniqueMedia.fromJson({
    'id': id,
    'kind': 'audio',
    'status': status,
    'sort_order': sortOrder,
    if (readUrl != null) 'read_url': readUrl,
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

void main() {
  test('A audio ready with read_url is parsed without storage_key', () {
    final media = ChroniqueMedia.fromJson({
      'id': 9,
      'kind': 'audio',
      'source_type': 'upload',
      'content_type': 'audio/mpeg',
      'status': 'ready',
      'sort_order': 0,
      'read_url': 'https://example.test/voix.mp3',
      'read_expires_at': '2026-09-25T10:16:00.000Z',
    });
    expect(media.readUrl, 'https://example.test/voix.mp3');
    expect(media.readExpiresAt, DateTime.parse('2026-09-25T10:16:00.000Z'));
    expect(chroniqueMediaIsDisplayableAudio(media), isTrue);
  });

  test('A pending audio is not displayable', () {
    expect(
      chroniqueMediaIsDisplayableAudio(_audio(id: 1, sortOrder: 0, status: 'pending_upload')),
      isFalse,
    );
  });

  test('A failed audio is not displayable', () {
    expect(
      chroniqueMediaIsDisplayableAudio(_audio(id: 1, sortOrder: 0, status: 'failed')),
      isFalse,
    );
  });

  test('A ready audio without read_url is not displayable', () {
    final media = ChroniqueMedia.fromJson({
      'id': 2,
      'kind': 'audio',
      'status': 'ready',
    });
    expect(media.readUrl, isNull);
    expect(chroniqueMediaIsDisplayableAudio(media), isFalse);
  });

  test('B only ready audio with read_url is displayable', () {
    expect(chroniqueMediaIsDisplayableAudio(_image(id: 1, sortOrder: 0)), isFalse);
    expect(chroniqueMediaIsDisplayableAudio(_video(id: 2, sortOrder: 1)), isFalse);
    expect(chroniqueMediaIsDisplayableImage(_audio(id: 3, sortOrder: 2)), isFalse);
    expect(chroniqueMediaIsDisplayableVideo(_audio(id: 3, sortOrder: 2)), isFalse);
    expect(chroniqueMediaIsDisplayableAudio(_audio(id: 3, sortOrder: 2)), isTrue);
  });

  testWidgets('C player receives exact readUrl and no Authorization', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueReadyAudioList(
          medias: [_audio(id: 8, sortOrder: 0, readUrl: 'https://example.test/voix.mp3')],
        ),
      ),
    );
    final player = tester.widget<ChroniqueReadyAudioPlayer>(find.byType(ChroniqueReadyAudioPlayer));
    expect(player.url, 'https://example.test/voix.mp3');
    expect(player.url.contains('Authorization'), isFalse);
    expect(player.url.toLowerCase().contains('bearer'), isFalse);
  });

  testWidgets('pending failed and image do not create an audio player', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueReadyAudioList(
          medias: [
            _audio(id: 1, sortOrder: 0, status: 'pending_upload'),
            _audio(id: 2, sortOrder: 1, status: 'failed'),
            _image(id: 3, sortOrder: 2),
            _video(id: 4, sortOrder: 3),
          ],
        ),
      ),
    );
    expect(find.byType(ChroniqueReadyAudioPlayer), findsNothing);
  });

  test('D clock format MM:SS and HH:MM:SS', () {
    expect(formatChroniqueAudioClock(Duration.zero), '00:00');
    expect(formatChroniqueAudioClock(const Duration(seconds: 5)), '00:05');
    expect(formatChroniqueAudioClock(const Duration(minutes: 3, seconds: 7)), '03:07');
    expect(formatChroniqueAudioClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '01:02:03');
    expect(formatChroniqueAudioClock(const Duration(seconds: 5)), formatChroniqueVideoClock(const Duration(seconds: 5)));
  });

  test('D slider and seek stay within duration without network', () {
    const duration = Duration(seconds: 10);
    expect(
      chroniqueVideoSliderValue(position: const Duration(seconds: 4), duration: duration),
      4000,
    );
    expect(chroniqueVideoSeekTarget(duration: duration, milliseconds: 2500), const Duration(milliseconds: 2500));
    expect(chroniqueVideoSeekTarget(duration: duration, milliseconds: 10000), duration);
    expect(chroniqueVideoSeekTarget(duration: duration, milliseconds: -5), Duration.zero);
    expect(chroniqueVideoSeekTarget(duration: Duration.zero, milliseconds: 100), Duration.zero);
  });

  test('E completed shows Play and not Pause', () {
    expect(
      chroniqueAudioShowsPauseIcon(
        playing: true,
        processingState: ProcessingState.ready,
        position: const Duration(seconds: 4),
        duration: const Duration(seconds: 10),
      ),
      isTrue,
    );
    expect(
      chroniqueAudioShowsPauseIcon(
        playing: false,
        processingState: ProcessingState.ready,
        position: const Duration(seconds: 4),
        duration: const Duration(seconds: 10),
      ),
      isFalse,
    );
    expect(
      chroniqueAudioShowsPauseIcon(
        playing: true,
        processingState: ProcessingState.completed,
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 10),
      ),
      isFalse,
    );
    expect(
      chroniqueAudioIsAtEnd(
        processingState: ProcessingState.completed,
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 10),
      ),
      isTrue,
    );
    expect(
      chroniqueAudioIsAtEnd(
        processingState: ProcessingState.ready,
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 10),
      ),
      isTrue,
    );
    expect(
      chroniqueAudioIsAtEnd(
        processingState: ProcessingState.ready,
        position: const Duration(seconds: 3),
        duration: const Duration(seconds: 10),
      ),
      isFalse,
    );
  });

  test('F several audios follow sort_order', () {
    final ordered = displayableChroniqueAudios([
      _audio(id: 3, sortOrder: 2, readUrl: 'https://example.test/c.mp3'),
      _audio(id: 1, sortOrder: 0, readUrl: 'https://example.test/a.mp3'),
      _audio(id: 2, sortOrder: 1, readUrl: 'https://example.test/b.mp3'),
    ]);
    expect(ordered.map((item) => item.readUrl).toList(), [
      'https://example.test/a.mp3',
      'https://example.test/b.mp3',
      'https://example.test/c.mp3',
    ]);
  });

  test('F mixed image audio video keep global sort_order', () {
    final mixed = displayableChroniqueRemoteMedia([
      _video(id: 3, sortOrder: 2, readUrl: 'https://example.test/clip.mp4'),
      _audio(id: 4, sortOrder: 3, readUrl: 'https://example.test/second.mp3'),
      _image(id: 5, sortOrder: 4, readUrl: 'https://example.test/last.jpg'),
      _audio(id: 2, sortOrder: 1, readUrl: 'https://example.test/first.mp3'),
      _image(id: 1, sortOrder: 0, readUrl: 'https://example.test/first.jpg'),
      ChroniqueMedia.fromJson({
        'id': 99,
        'kind': 'document',
        'status': 'ready',
        'sort_order': 5,
        'read_url': 'https://example.test/note.pdf',
      }),
      _audio(id: 50, sortOrder: 6, status: 'pending_upload'),
    ]);
    expect(mixed.map((item) => item.kind).toList(), ['image', 'audio', 'video', 'audio', 'image']);
    expect(mixed.map((item) => item.readUrl).toList(), [
      'https://example.test/first.jpg',
      'https://example.test/first.mp3',
      'https://example.test/clip.mp4',
      'https://example.test/second.mp3',
      'https://example.test/last.jpg',
    ]);
  });

  testWidgets('F mixed list builds image audio video audio image', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChroniqueReadyRemoteMediaList(
          medias: [
            _image(id: 1, sortOrder: 0, readUrl: 'https://example.test/first.jpg'),
            _audio(id: 2, sortOrder: 1, readUrl: 'https://example.test/first.mp3'),
            _video(id: 3, sortOrder: 2, readUrl: 'https://example.test/clip.mp4'),
            _audio(id: 4, sortOrder: 3, readUrl: 'https://example.test/second.mp3'),
            _image(id: 5, sortOrder: 4, readUrl: 'https://example.test/last.jpg'),
          ],
        ),
      ),
    );
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(2));
    expect((images[0].image as NetworkImage).url, 'https://example.test/first.jpg');
    expect((images[1].image as NetworkImage).url, 'https://example.test/last.jpg');
    expect((images[0].image as NetworkImage).headers, isNull);

    final audios = tester.widgetList<ChroniqueReadyAudioPlayer>(find.byType(ChroniqueReadyAudioPlayer)).toList();
    expect(audios, hasLength(2));
    expect(audios[0].url, 'https://example.test/first.mp3');
    expect(audios[1].url, 'https://example.test/second.mp3');

    final video = tester.widget<ChroniqueReadyVideoPlayer>(find.byType(ChroniqueReadyVideoPlayer));
    expect(video.url, 'https://example.test/clip.mp4');

    final firstImage = find.byType(Image).first;
    final firstAudio = find.byType(ChroniqueReadyAudioPlayer).first;
    final videoFinder = find.byType(ChroniqueReadyVideoPlayer);
    final lastAudio = find.byType(ChroniqueReadyAudioPlayer).last;
    final lastImage = find.byType(Image).last;
    expect(tester.getTopLeft(firstImage).dy < tester.getTopLeft(firstAudio).dy, isTrue);
    expect(tester.getTopLeft(firstAudio).dy < tester.getTopLeft(videoFinder).dy, isTrue);
    expect(tester.getTopLeft(videoFinder).dy < tester.getTopLeft(lastAudio).dy, isTrue);
    expect(tester.getTopLeft(lastAudio).dy < tester.getTopLeft(lastImage).dy, isTrue);
  });
}
