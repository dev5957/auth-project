import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'chronique_local_file_access.dart';

/// Extraction JPEG locale d’une frame vidéo. Aucun appel réseau.
abstract class ChroniqueVideoThumbnailExtractor {
  Future<String?> extractJpeg({required String videoPath});
}

const int kChroniqueVideoThumbnailMaxWidth = 480;
const int kChroniqueVideoThumbnailQuality = 70;
const int kChroniqueVideoThumbnailTimeMs = 1000;
const int kChroniqueVideoThumbnailFallbackTimeMs = 250;

/// Appel plugin (`VideoThumbnail.thumbnailFile`) injectable pour les tests.
typedef ChroniqueVideoThumbnailGrabber = Future<String?> Function({
  required String videoPath,
  required String directory,
  required int timeMs,
});

/// `video_thumbnail` (Android / iOS). Échec → `null`, jamais d’exception métier.
///
/// Le plugin ne signale un chemin que s’il le retourne. Un `throw` avant le
/// retour ne permet pas de connaître un fichier éventuellement créé.
class DeviceChroniqueVideoThumbnailExtractor implements ChroniqueVideoThumbnailExtractor {
  const DeviceChroniqueVideoThumbnailExtractor({
    this.grabber,
    this.files = const IoChroniqueLocalFileAccess(),
    this.temporaryDirectoryPath,
  });

  final ChroniqueVideoThumbnailGrabber? grabber;
  final ChroniqueLocalFileAccess files;
  final Future<String> Function()? temporaryDirectoryPath;

  @override
  Future<String?> extractJpeg({required String videoPath}) async {
    final path = videoPath.trim();
    if (path.isEmpty) {
      return null;
    }
    try {
      final directory = await _tempDirectory();
      final first = await _extract(path, directory, kChroniqueVideoThumbnailTimeMs);
      if (first != null) {
        return first;
      }
      return await _extract(path, directory, kChroniqueVideoThumbnailFallbackTimeMs);
    } catch (error) {
      debugPrint('[chronique-video-thumb] extract failed');
      return null;
    }
  }

  Future<String> _tempDirectory() async {
    final override = temporaryDirectoryPath;
    if (override != null) {
      return override();
    }
    final directory = await getTemporaryDirectory();
    return directory.path;
  }

  Future<String?> _grab({
    required String videoPath,
    required String directory,
    required int timeMs,
  }) {
    final custom = grabber;
    if (custom != null) {
      return custom(videoPath: videoPath, directory: directory, timeMs: timeMs);
    }
    return VideoThumbnail.thumbnailFile(
      video: videoPath,
      thumbnailPath: directory,
      imageFormat: ImageFormat.JPEG,
      maxWidth: kChroniqueVideoThumbnailMaxWidth,
      quality: kChroniqueVideoThumbnailQuality,
      timeMs: timeMs,
    );
  }

  Future<String?> _extract(String videoPath, String directory, int timeMs) async {
    String? knownJpeg;
    try {
      final filePath = await _grab(
        videoPath: videoPath,
        directory: directory,
        timeMs: timeMs,
      );
      if (filePath == null || filePath.trim().isEmpty) {
        return null;
      }
      knownJpeg = filePath.trim();
      if (knownJpeg == videoPath.trim()) {
        return null;
      }
      final file = File(knownJpeg);
      if (!file.existsSync() || file.lengthSync() < 1) {
        await _discardKnownJpeg(knownJpeg, videoPath);
        return null;
      }
      return file.path;
    } catch (error) {
      debugPrint('[chronique-video-thumb] extract failed');
      await _discardKnownJpeg(knownJpeg, videoPath);
      return null;
    }
  }

  Future<void> _discardKnownJpeg(String? jpegPath, String videoPath) async {
    final trimmed = jpegPath?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }
    if (trimmed == videoPath.trim()) {
      return;
    }
    try {
      await files.deleteQuietly(trimmed);
    } catch (error) {
      debugPrint('[chronique-video-thumb] temp jpeg delete failed');
    }
  }
}
