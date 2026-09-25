import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/media_draft.dart';
import 'chronique_local_media_picker.dart';
import 'chronique_media_mime.dart';
import 'chronique_microphone_recorder.dart';

/// `record` 7.x : AAC-LC dans un conteneur MPEG-4 (`.m4a` → `audio/mp4`).
class DeviceChroniqueMicrophoneRecorder implements ChroniqueMicrophoneRecorder {
  DeviceChroniqueMicrophoneRecorder({
    AudioRecorder? recorder,
  }) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _activePath;

  static const _config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    numChannels: 1,
  );

  @override
  Future<bool> hasPermission() {
    return _recorder.hasPermission();
  }

  @override
  Future<void> start() async {
    await discard();
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/chronique-mic-${DateTime.now().millisecondsSinceEpoch}.m4a';
    _activePath = path;
    await _recorder.start(_config, path: path);
  }

  @override
  Future<MediaPickResult> stop() async {
    try {
      final stoppedPath = (await _recorder.stop())?.trim();
      final path = (stoppedPath != null && stoppedPath.isNotEmpty)
          ? stoppedPath
          : _activePath?.trim();
      _activePath = path;
      if (path == null || path.isEmpty) {
        return const MediaPickFailed(kMediaInaccessibleMessage);
      }
      final file = File(path);
      if (!file.existsSync()) {
        return const MediaPickFailed(kMediaInaccessibleMessage);
      }
      final byteSize = file.lengthSync();
      if (byteSize < 1) {
        _deleteQuietly(path);
        return const MediaPickFailed(kMediaInaccessibleMessage);
      }
      final fileName = _nameOf(path);
      final contentType = resolveChroniqueMediaContentType(
        kind: MediaDraftKind.audio,
        fileName: fileName,
        localPath: path,
        platformMime: 'audio/mp4',
      );
      if (contentType == null) {
        _deleteQuietly(path);
        return const MediaPickFailed(kMediaUnsupportedMessage);
      }
      return MediaPickSelected(
        kind: MediaDraftKind.audio,
        sourceType: MediaDraftSourceType.microphone,
        fileName: fileName,
        byteSize: byteSize,
        localPath: path,
        contentType: contentType,
        platformMime: 'audio/mp4',
      );
    } on Exception {
      return const MediaPickFailed(kMediaInaccessibleMessage);
    }
  }

  @override
  void keep() {
    _activePath = null;
  }

  @override
  Future<void> discard() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.cancel();
      }
    } on Exception {
      // Le fichier est quand même retiré ci-dessous.
    }
    final path = _activePath;
    _activePath = null;
    if (path != null) {
      _deleteQuietly(path);
    }
  }

  @override
  Future<void> dispose() async {
    await discard();
    await _recorder.dispose();
  }

  void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } on Exception {
      // Fichier temporaire : l’OS le nettoiera.
    }
  }

  String _nameOf(String path) {
    final slash = path.replaceAll('\\', '/').split('/').last;
    return slash.isEmpty ? 'enregistrement.m4a' : slash;
  }
}
