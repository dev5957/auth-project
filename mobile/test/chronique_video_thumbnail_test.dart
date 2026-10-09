import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/chronique/media/chronique_local_file_access.dart';
import 'package:mobile/features/chronique/media/chronique_video_thumbnail.dart';

class _RecordingFiles implements ChroniqueLocalFileAccess {
  bool failDelete = false;
  final List<String> deleted = [];

  @override
  Future<bool> isReadable(String path) async => true;

  @override
  Future<int> lengthOf(String path) async => 1;

  @override
  Future<void> deleteQuietly(String path, {bool Function()? ifStillUnused}) async {
    if (ifStillUnused != null && !ifStillUnused()) {
      return;
    }
    deleted.add(path);
    if (failDelete) {
      throw Exception('delete failed');
    }
  }
}

class _ScriptedGrabber {
  _ScriptedGrabber(this.steps);

  final List<Future<String?> Function()> steps;
  final List<int> timeMsSeen = [];
  var calls = 0;

  Future<String?> call({
    required String videoPath,
    required String directory,
    required int timeMs,
  }) {
    timeMsSeen.add(timeMs);
    if (calls >= steps.length) {
      throw StateError('unexpected grabber call ${calls + 1}');
    }
    final step = steps[calls];
    calls += 1;
    return step();
  }
}

Future<File> _jpeg(String name, {List<int> bytes = const [1, 2, 3]}) async {
  final file = File('${Directory.systemTemp.path}/$name');
  await file.writeAsBytes(bytes);
  addTearDown(() {
    if (file.existsSync()) {
      file.deleteSync();
    }
  });
  return file;
}

void main() {
  const video = '/tmp/source-clip.mp4';

  test('keeps the first valid JPEG and does not delete it', () async {
    final files = _RecordingFiles();
    final first = await _jpeg('chronique-extract-keep.jpg');
    final grabber = _ScriptedGrabber([() async => first.path]);
    final extractor = DeviceChroniqueVideoThumbnailExtractor(
      grabber: grabber.call,
      files: files,
      temporaryDirectoryPath: () async => Directory.systemTemp.path,
    );
    final result = await extractor.extractJpeg(videoPath: video);
    expect(result, first.path);
    expect(files.deleted, isEmpty);
    expect(grabber.calls, 1);
    expect(grabber.timeMsSeen, [kChroniqueVideoThumbnailTimeMs]);
  });

  test('deletes an invalid first JPEG then keeps the fallback', () async {
    final files = _RecordingFiles();
    final invalid = await _jpeg('chronique-extract-invalid.jpg', bytes: const []);
    final valid = await _jpeg('chronique-extract-fallback.jpg');
    final grabber = _ScriptedGrabber([
      () async => invalid.path,
      () async => valid.path,
    ]);
    final extractor = DeviceChroniqueVideoThumbnailExtractor(
      grabber: grabber.call,
      files: files,
      temporaryDirectoryPath: () async => Directory.systemTemp.path,
    );
    final result = await extractor.extractJpeg(videoPath: video);
    expect(result, valid.path);
    expect(files.deleted, [invalid.path]);
    expect(files.deleted, isNot(contains(valid.path)));
    expect(files.deleted, isNot(contains(video)));
    expect(grabber.timeMsSeen, [
      kChroniqueVideoThumbnailTimeMs,
      kChroniqueVideoThumbnailFallbackTimeMs,
    ]);
  });

  test('first plugin throw without a returned path cannot be cleaned, fallback is kept', () async {
    final files = _RecordingFiles();
    final leaked = await _jpeg('chronique-extract-unknown-leak.jpg');
    final valid = await _jpeg('chronique-extract-after-unknown.jpg');
    final grabber = _ScriptedGrabber([
      () async {
        throw Exception('plugin failed after creating ${leaked.path}');
      },
      () async => valid.path,
    ]);
    final extractor = DeviceChroniqueVideoThumbnailExtractor(
      grabber: grabber.call,
      files: files,
      temporaryDirectoryPath: () async => Directory.systemTemp.path,
    );
    final result = await extractor.extractJpeg(videoPath: video);
    expect(result, valid.path);
    expect(files.deleted, isEmpty, reason: 'chemin jamais retourné par le plugin');
    expect(leaked.existsSync(), isTrue);
  });

  test('cleans a known path when the first file is missing then keeps fallback', () async {
    final files = _RecordingFiles();
    final missing = '${Directory.systemTemp.path}/chronique-extract-missing-stat.jpg';
    final valid = await _jpeg('chronique-extract-after-stat.jpg');
    final grabber = _ScriptedGrabber([
      () async => missing,
      () async => valid.path,
    ]);
    final extractor = DeviceChroniqueVideoThumbnailExtractor(
      grabber: grabber.call,
      files: files,
      temporaryDirectoryPath: () async => Directory.systemTemp.path,
    );
    final result = await extractor.extractJpeg(videoPath: video);
    expect(result, valid.path);
    expect(files.deleted, [missing]);
  });

  test('both attempts failing clean every known intermediate JPEG', () async {
    final files = _RecordingFiles();
    final first = await _jpeg('chronique-extract-both-a.jpg', bytes: const []);
    final second = await _jpeg('chronique-extract-both-b.jpg', bytes: const []);
    final grabber = _ScriptedGrabber([
      () async => first.path,
      () async => second.path,
    ]);
    final extractor = DeviceChroniqueVideoThumbnailExtractor(
      grabber: grabber.call,
      files: files,
      temporaryDirectoryPath: () async => Directory.systemTemp.path,
    );
    final result = await extractor.extractJpeg(videoPath: video);
    expect(result, isNull);
    expect(files.deleted, [first.path, second.path]);
    expect(files.deleted, isNot(contains(video)));
  });

  test('delete failure does not hide a valid fallback JPEG', () async {
    final files = _RecordingFiles()..failDelete = true;
    final invalid = await _jpeg('chronique-extract-delete-fail.jpg', bytes: const []);
    final valid = await _jpeg('chronique-extract-delete-fail-ok.jpg');
    final grabber = _ScriptedGrabber([
      () async => invalid.path,
      () async => valid.path,
    ]);
    final extractor = DeviceChroniqueVideoThumbnailExtractor(
      grabber: grabber.call,
      files: files,
      temporaryDirectoryPath: () async => Directory.systemTemp.path,
    );
    final result = await extractor.extractJpeg(videoPath: video);
    expect(result, valid.path);
    expect(files.deleted, [invalid.path]);
  });

  test('never treats the source video path as a thumbnail to delete', () async {
    final files = _RecordingFiles();
    final grabber = _ScriptedGrabber([
      () async => video,
      () async => video,
    ]);
    final extractor = DeviceChroniqueVideoThumbnailExtractor(
      grabber: grabber.call,
      files: files,
      temporaryDirectoryPath: () async => Directory.systemTemp.path,
    );
    final result = await extractor.extractJpeg(videoPath: video);
    expect(result, isNull);
    expect(files.deleted, isEmpty);
  });
}
