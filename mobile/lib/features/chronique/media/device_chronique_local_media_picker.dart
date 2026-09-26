import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/media_draft.dart';
import 'chronique_local_media_picker.dart';
import 'chronique_media_mime.dart';

const _documentExtensions = {'pdf', 'doc', 'docx', 'txt'};

/// ImagePicker (galerie multi-images / caméra) + FilePicker (vidéos, audio, documents).
class DeviceChroniqueLocalMediaPicker implements ChroniqueLocalMediaPicker {
  DeviceChroniqueLocalMediaPicker({
    ImagePicker? imagePicker,
  }) : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  Future<MediaPickResult> pickImage({int? limit}) {
    return _pickManyWithImagePicker(
      kind: MediaDraftKind.image,
      sourceType: MediaDraftSourceType.gallery,
      pick: () => _imagePicker.pickMultiImage(limit: limit),
    );
  }

  @override
  Future<MediaPickResult> pickImageFromCamera() {
    return _pickSingleWithImagePicker(
      kind: MediaDraftKind.image,
      sourceType: MediaDraftSourceType.camera,
      pick: () => _imagePicker.pickImage(source: ImageSource.camera),
    );
  }

  @override
  Future<MediaPickResult> pickVideo({int? limit}) {
    return _pickWithFilePicker(
      kind: MediaDraftKind.video,
      sourceType: MediaDraftSourceType.gallery,
      type: FileType.video,
      allowMultiple: true,
    );
  }

  @override
  Future<MediaPickResult> pickVideoFromCamera() {
    return _pickSingleWithImagePicker(
      kind: MediaDraftKind.video,
      sourceType: MediaDraftSourceType.camera,
      pick: () => _imagePicker.pickVideo(source: ImageSource.camera),
    );
  }

  @override
  Future<MediaPickResult> pickAudio() {
    return _pickWithFilePicker(
      kind: MediaDraftKind.audio,
      sourceType: MediaDraftSourceType.upload,
      type: FileType.audio,
      allowMultiple: false,
    );
  }

  @override
  Future<MediaPickResult> pickDocument({int? limit}) {
    return _pickWithFilePicker(
      kind: MediaDraftKind.document,
      sourceType: MediaDraftSourceType.upload,
      type: FileType.custom,
      allowedExtensions: _documentExtensions.toList(),
      allowMultiple: true,
    );
  }

  Future<MediaPickResult> _pickManyWithImagePicker({
    required MediaDraftKind kind,
    required MediaDraftSourceType sourceType,
    required Future<List<XFile>> Function() pick,
  }) async {
    try {
      final files = await pick();
      if (files.isEmpty) {
        return const MediaPickCancelled();
      }
      final items = <MediaPickSelected>[];
      for (final file in files) {
        final selected = await _selectedFromXFile(
          file,
          kind: kind,
          sourceType: sourceType,
        );
        if (selected != null) {
          items.add(selected);
        }
      }
      if (items.isEmpty) {
        return const MediaPickFailed(kMediaUnsupportedMessage);
      }
      return MediaPickMany(items);
    } on PlatformException catch (error) {
      if (sourceType == MediaDraftSourceType.camera && _isCameraAccessDenied(error)) {
        return const MediaPickFailed(kCameraAccessDeniedMessage);
      }
      return const MediaPickFailed(kMediaInaccessibleMessage);
    } on Exception {
      return const MediaPickFailed(kMediaInaccessibleMessage);
    }
  }

  Future<MediaPickResult> _pickSingleWithImagePicker({
    required MediaDraftKind kind,
    required MediaDraftSourceType sourceType,
    required Future<XFile?> Function() pick,
  }) async {
    try {
      final file = await pick();
      if (file == null) {
        return const MediaPickCancelled();
      }
      final selected = await _selectedFromXFile(
        file,
        kind: kind,
        sourceType: sourceType,
      );
      if (selected == null) {
        return const MediaPickFailed(kMediaUnsupportedMessage);
      }
      return selected;
    } on PlatformException catch (error) {
      if (sourceType == MediaDraftSourceType.camera && _isCameraAccessDenied(error)) {
        return const MediaPickFailed(kCameraAccessDeniedMessage);
      }
      return const MediaPickFailed(kMediaInaccessibleMessage);
    } on Exception {
      return const MediaPickFailed(kMediaInaccessibleMessage);
    }
  }

  bool _isCameraAccessDenied(PlatformException error) {
    final code = error.code.toLowerCase();
    final message = (error.message ?? '').toLowerCase();
    return (code.contains('camera') && code.contains('denied')) ||
        code.contains('permission') ||
        (message.contains('camera') && message.contains('denied'));
  }

  Future<MediaPickSelected?> _selectedFromXFile(
    XFile file, {
    required MediaDraftKind kind,
    required MediaDraftSourceType sourceType,
  }) async {
    final path = file.path.trim();
    if (path.isEmpty) {
      return null;
    }
    final byteSize = await file.length();
    if (byteSize < 1) {
      return null;
    }
    final name = _nameOf(file.name, path);
    final platformMime = file.mimeType;
    final contentType = resolveChroniqueMediaContentType(
      kind: kind,
      fileName: name,
      localPath: path,
      platformMime: platformMime,
    );
    return MediaPickSelected(
      kind: kind,
      sourceType: sourceType,
      fileName: name,
      byteSize: byteSize,
      localPath: path,
      contentType: contentType,
      platformMime: platformMime,
    );
  }

  Future<MediaPickResult> _pickWithFilePicker({
    required MediaDraftKind kind,
    required MediaDraftSourceType sourceType,
    required FileType type,
    List<String>? allowedExtensions,
    required bool allowMultiple,
  }) async {
    try {
      final result = await FilePicker.pickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
        allowMultiple: allowMultiple,
      );
      if (result == null || result.files.isEmpty) {
        return const MediaPickCancelled();
      }
      final items = <MediaPickSelected>[];
      var sawUnsupported = false;
      var sawInaccessible = false;
      for (final file in result.files) {
        final path = file.path?.trim();
        if (path == null || path.isEmpty) {
          sawInaccessible = true;
          continue;
        }
        final extension = _extensionOf(file.name.isNotEmpty ? file.name : path);
        if (kind == MediaDraftKind.document &&
            !_documentExtensions.contains(extension)) {
          sawUnsupported = true;
          continue;
        }
        final byteSize = file.size > 0 ? file.size : _lengthOf(path);
        if (byteSize < 1) {
          sawInaccessible = true;
          continue;
        }
        final name = _nameOf(file.name, path);
        final contentType = resolveChroniqueMediaContentType(
          kind: kind,
          fileName: name,
          localPath: path,
        );
        if (contentType == null) {
          sawUnsupported = true;
          continue;
        }
        items.add(
          MediaPickSelected(
            kind: kind,
            sourceType: sourceType,
            fileName: name,
            byteSize: byteSize,
            localPath: path,
            contentType: contentType,
          ),
        );
      }
      if (items.isEmpty) {
        if (sawUnsupported) {
          return const MediaPickFailed(kMediaUnsupportedMessage);
        }
        if (sawInaccessible) {
          return const MediaPickFailed(kMediaInaccessibleMessage);
        }
        return const MediaPickFailed(kMediaInaccessibleMessage);
      }
      if (!allowMultiple && items.length == 1) {
        return items.single;
      }
      return MediaPickMany(items);
    } on Exception {
      return const MediaPickFailed(kMediaInaccessibleMessage);
    }
  }

  int _lengthOf(String path) {
    try {
      return File(path).lengthSync();
    } on Exception {
      return 0;
    }
  }

  String _nameOf(String name, String path) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    final slash = path.replaceAll('\\', '/').split('/').last;
    return slash.isEmpty ? 'Sans nom' : slash;
  }

  String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }
}
