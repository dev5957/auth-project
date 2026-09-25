import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/media_draft.dart';
import 'chronique_local_media_picker.dart';
import 'chronique_media_mime.dart';

const _documentExtensions = {'pdf', 'doc', 'docx', 'txt'};

/// ImagePicker (galerie / caméra photo et vidéo) + FilePicker (audio / documents).
class DeviceChroniqueLocalMediaPicker implements ChroniqueLocalMediaPicker {
  DeviceChroniqueLocalMediaPicker({
    ImagePicker? imagePicker,
  }) : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  Future<MediaPickResult> pickImage() {
    return _pickWithImagePicker(
      kind: MediaDraftKind.image,
      sourceType: MediaDraftSourceType.gallery,
      pick: () => _imagePicker.pickImage(source: ImageSource.gallery),
    );
  }

  @override
  Future<MediaPickResult> pickImageFromCamera() {
    return _pickWithImagePicker(
      kind: MediaDraftKind.image,
      sourceType: MediaDraftSourceType.camera,
      pick: () => _imagePicker.pickImage(source: ImageSource.camera),
    );
  }

  @override
  Future<MediaPickResult> pickVideo() {
    return _pickWithImagePicker(
      kind: MediaDraftKind.video,
      sourceType: MediaDraftSourceType.gallery,
      pick: () => _imagePicker.pickVideo(source: ImageSource.gallery),
    );
  }

  @override
  Future<MediaPickResult> pickVideoFromCamera() {
    return _pickWithImagePicker(
      kind: MediaDraftKind.video,
      sourceType: MediaDraftSourceType.camera,
      pick: () => _imagePicker.pickVideo(source: ImageSource.camera),
    );
  }

  @override
  Future<MediaPickResult> pickAudio() {
    return _pickWithFilePicker(
      kind: MediaDraftKind.audio,
      type: FileType.audio,
    );
  }

  @override
  Future<MediaPickResult> pickDocument() {
    return _pickWithFilePicker(
      kind: MediaDraftKind.document,
      type: FileType.custom,
      allowedExtensions: _documentExtensions.toList(),
    );
  }

  Future<MediaPickResult> _pickWithImagePicker({
    required MediaDraftKind kind,
    required MediaDraftSourceType sourceType,
    required Future<XFile?> Function() pick,
  }) async {
    try {
      final file = await pick();
      if (file == null) {
        return const MediaPickCancelled();
      }
      final path = file.path.trim();
      if (path.isEmpty) {
        return const MediaPickFailed(kMediaInaccessibleMessage);
      }
      final byteSize = await file.length();
      if (byteSize < 1) {
        return const MediaPickFailed(kMediaInaccessibleMessage);
      }
      final name = _nameOf(file.name, path);
      final platformMime = file.mimeType;
      final contentType = resolveChroniqueMediaContentType(
        kind: kind,
        fileName: name,
        localPath: path,
        platformMime: platformMime,
      );
      if (contentType == null) {
        return const MediaPickFailed(kMediaUnsupportedMessage);
      }
      return MediaPickSelected(
        kind: kind,
        sourceType: sourceType,
        fileName: name,
        byteSize: byteSize,
        localPath: path,
        contentType: contentType,
        platformMime: platformMime,
      );
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

  Future<MediaPickResult> _pickWithFilePicker({
    required MediaDraftKind kind,
    required FileType type,
    List<String>? allowedExtensions,
  }) async {
    try {
      final result = await FilePicker.pickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) {
        return const MediaPickCancelled();
      }
      final file = result.files.single;
      final path = file.path?.trim();
      if (path == null || path.isEmpty) {
        return const MediaPickFailed(kMediaInaccessibleMessage);
      }
      final extension = _extensionOf(file.name.isNotEmpty ? file.name : path);
      if (kind == MediaDraftKind.document &&
          !_documentExtensions.contains(extension)) {
        return const MediaPickFailed(kMediaUnsupportedMessage);
      }
      final byteSize = file.size > 0 ? file.size : _lengthOf(path);
      if (byteSize < 1) {
        return const MediaPickFailed(kMediaInaccessibleMessage);
      }
      final name = _nameOf(file.name, path);
      final contentType = resolveChroniqueMediaContentType(
        kind: kind,
        fileName: name,
        localPath: path,
      );
      if (contentType == null) {
        return const MediaPickFailed(kMediaUnsupportedMessage);
      }
      return MediaPickSelected(
        kind: kind,
        sourceType: MediaDraftSourceType.upload,
        fileName: name,
        byteSize: byteSize,
        localPath: path,
        contentType: contentType,
      );
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
