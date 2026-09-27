import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../media/chronique_local_file_access.dart';
import '../../media/chronique_local_media_picker.dart';
import '../../media/chronique_media_limits.dart';
import '../../media/chronique_media_mime.dart';
import '../../media/chronique_video_thumbnail.dart';
import '../../models/chronique.dart';
import '../../models/chronique_draft.dart';
import '../../models/chronique_media_upload.dart';
import '../../models/media_draft.dart';
import '../../providers/chronique_providers.dart';
import '../../services/chronique_media_upload_client.dart';

/// Brouillon local (texte + médias) + pipeline create → URL signée → PUT R2 → complete.
class CreateChroniqueController extends AutoDisposeNotifier<ChroniqueDraft> {
  int _nextMediaId = 0;
  int _draftGeneration = 0;
  final Map<int, Future<void>> _thumbnailTasks = {};
  final Map<String, Future<void>> _thumbnailDeletes = {};
  /// Chemins des fichiers source choisis par l’utilisateur. Jamais recyclés
  /// comme cibles de suppression de miniature, y compris après `clearDraft()`.
  final Set<String> _userSourcePaths = {};

  ChroniqueLocalMediaPicker get _picker =>
      ref.read(chroniqueLocalMediaPickerProvider);

  ChroniqueLocalFileAccess get _files =>
      ref.read(chroniqueLocalFileAccessProvider);

  ChroniqueMediaUploadClient get _uploadClient =>
      ref.read(chroniqueMediaUploadClientProvider);

  ChroniqueVideoThumbnailExtractor get _thumbnails =>
      ref.read(chroniqueVideoThumbnailExtractorProvider);

  @override
  ChroniqueDraft build() => const ChroniqueDraft();

  void saveDraft({String? title, String? body}) {
    state = state.copyWith(
      title: title ?? state.title,
      body: body ?? state.body,
    );
  }

  void addMediaDraft({
    required MediaDraftKind kind,
    MediaDraftSourceType? sourceType,
    String? fileName,
    int? byteSize,
    String? localPath,
    String? localThumbnailPath,
    String? contentType,
    MediaDraftStatus status = MediaDraftStatus.selected,
  }) {
    _nextMediaId += 1;
    _rememberUserSource(localPath);
    state = state.copyWith(
      medias: [
        ...state.medias,
        MediaDraft(
          id: _nextMediaId,
          kind: kind,
          sourceType: sourceType ?? MediaDraft.defaultSourceFor(kind),
          fileName: fileName,
          byteSize: byteSize,
          localPath: localPath,
          localThumbnailPath: localThumbnailPath,
          contentType: contentType,
          status: status,
        ),
      ],
    );
  }

  void removeMediaDraft(int id) {
    MediaDraft? removed;
    final remaining = <MediaDraft>[];
    for (final media in state.medias) {
      if (media.id == id) {
        removed = media;
      } else {
        remaining.add(media);
      }
    }
    final protected = {
      ..._sourcePathsOf(remaining),
      ..._sourcePathsOf([if (removed != null) removed]),
    };
    state = state.copyWith(medias: remaining);
    _thumbnailTasks.remove(id);
    final thumb = removed?.localThumbnailPath;
    if (thumb != null && thumb.trim().isNotEmpty) {
      unawaited(_deleteThumbnailIfUnused(thumb, extraProtected: protected));
    }
  }

  void clearDraft() {
    _draftGeneration += 1;
    final thumbs = <String>[
      for (final media in state.medias)
        if (media.localThumbnailPath != null &&
            media.localThumbnailPath!.trim().isNotEmpty)
          media.localThumbnailPath!.trim(),
    ];
    final protected = _sourcePathsOf(state.medias);
    _thumbnailTasks.clear();
    // Ne jamais réinitialiser `_nextMediaId` : une extraction obsolète
    // ne doit pas pouvoir cibler un nouveau média par collision d’id.
    state = const ChroniqueDraft();
    for (final thumb in thumbs) {
      unawaited(_deleteThumbnailIfUnused(thumb, extraProtected: protected));
    }
  }

  Future<String?> pickImage() {
    return _pick(() => _picker.pickImage(limit: _remainingSlots));
  }

  Future<String?> pickImageFromCamera() => _pick(_picker.pickImageFromCamera);

  Future<String?> pickVideo() {
    return _pick(() => _picker.pickVideo(limit: _remainingSlots));
  }

  Future<String?> pickVideoFromCamera() => _pick(_picker.pickVideoFromCamera);

  Future<String?> pickAudio() => _pick(_picker.pickAudio);

  Future<String?> pickDocument() {
    return _pick(() => _picker.pickDocument(limit: _remainingSlots));
  }

  int get _remainingSlots =>
      kChroniqueMaxMediaCount - state.medias.length;

  Future<String?> applyMediaPick(MediaPickResult result) {
    return _applyPick(result);
  }

  Future<String?> _pick(Future<MediaPickResult> Function() pick) async {
    if (_remainingSlots <= 0) {
      return kTooManyMediaMessage;
    }
    return _applyPick(await pick());
  }

  Future<String?> _applyPick(MediaPickResult result) async {
    switch (result) {
      case MediaPickCancelled():
        return null;
      case MediaPickFailed(:final message):
        return message;
      case MediaPickSelected():
        return _applySelections([result]);
      case MediaPickMany(:final items):
        return _applySelections(items);
    }
  }

  Future<String?> _applySelections(List<MediaPickSelected> items) async {
    if (items.isEmpty) {
      return null;
    }

    final existingPaths = <String>{
      for (final media in state.medias)
        if (media.localPath != null && media.localPath!.trim().isNotEmpty)
          media.localPath!.trim(),
    };
    var usedBytes = chroniqueDraftMediaBytes(state.medias);

    var remaining = _remainingSlots;
    var skippedLimit = false;
    var skippedFormat = false;
    var skippedSize = false;
    var skippedInaccessible = false;
    final accepted = <MediaDraft>[];

    for (final item in items) {
      final path = item.localPath.trim();
      if (path.isEmpty || item.byteSize < 1) {
        skippedInaccessible = true;
        continue;
      }
      if (existingPaths.contains(path)) {
        continue;
      }
      final mime = item.contentType ??
          resolveChroniqueMediaContentType(
            kind: item.kind,
            fileName: item.fileName,
            localPath: path,
            platformMime: item.platformMime,
          );
      if (mime == null || !isChroniqueContentTypeAllowed(item.kind, mime)) {
        skippedFormat = true;
        continue;
      }
      if (item.byteSize > kChroniqueMaxMediaBytes ||
          usedBytes + item.byteSize > kChroniqueMaxMediaBytes) {
        skippedSize = true;
        continue;
      }
      if (remaining <= 0) {
        skippedLimit = true;
        continue;
      }
      _nextMediaId += 1;
      _rememberUserSource(path);
      accepted.add(
        MediaDraft(
          id: _nextMediaId,
          kind: item.kind,
          sourceType: item.sourceType,
          fileName: item.fileName,
          byteSize: item.byteSize,
          localPath: path,
          contentType: mime,
        ),
      );
      existingPaths.add(path);
      usedBytes += item.byteSize;
      remaining -= 1;
    }

    if (accepted.isNotEmpty) {
      state = state.copyWith(medias: [...state.medias, ...accepted]);
      for (final media in accepted) {
        if (media.kind == MediaDraftKind.video) {
          _startVideoThumbnail(media.id);
        }
      }
    }

    if (skippedLimit) {
      return kSomeMediaSkippedLimitMessage;
    }
    if (accepted.isNotEmpty) {
      if (skippedFormat) {
        return kMediaUnsupportedMessage;
      }
      if (skippedSize) {
        return kMediaQuotaExceededMessage;
      }
      if (skippedInaccessible) {
        return kMediaInaccessibleMessage;
      }
      return null;
    }
    if (skippedFormat) {
      return kMediaUnsupportedMessage;
    }
    if (skippedSize) {
      return kMediaQuotaExceededMessage;
    }
    if (skippedInaccessible) {
      return kMediaInaccessibleMessage;
    }
    return null;
  }

  /// Contrôles UX locaux. Ne commence pas `POST /chroniques` si invalide.
  Future<String?> validateMediaForPublish() async {
    final medias = state.medias;
    if (medias.length > kChroniqueMaxMediaCount) {
      return kTooManyMediaMessage;
    }
    var totalBytes = 0;
    for (final media in medias) {
      if (media.isUploaded) {
        totalBytes += media.byteSize ?? 0;
        continue;
      }
      final path = media.localPath?.trim();
      if (path == null || path.isEmpty) {
        return kMediaInaccessibleMessage;
      }
      final readable = await _files.isReadable(path);
      if (!readable) {
        return kMediaInaccessibleMessage;
      }
      final size = media.byteSize ?? await _files.lengthOf(path);
      if (size < 1) {
        return kMediaInaccessibleMessage;
      }
      totalBytes += size;
      if (!isChroniqueContentTypeAllowed(media.kind, media.contentType)) {
        return kMediaUnsupportedMessage;
      }
    }
    if (totalBytes > kChroniqueMaxMediaBytes) {
      return kMediaQuotaExceededMessage;
    }
    return null;
  }

  /// `POST /chroniques` puis, s’il y a des médias, init / PUT R2 / complete.
  Future<Chronique> publish({
    required String body,
    String? title,
    String publish = 'now',
    String? scheduledAt,
    bool isTimeLimited = false,
    String? expiresAt,
  }) async {
    final mediaError = await validateMediaForPublish();
    if (mediaError != null) {
      throw ApiException(message: mediaError, statusCode: 400);
    }

    final repository = ref.read(chroniqueRepositoryProvider);
    late Chronique chronique;
    final existingId = state.createdChroniqueId;
    if (existingId != null) {
      chronique = Chronique(
        id: existingId,
        body: body,
        title: title,
        status: publish == 'schedule' ? 'scheduled' : 'active',
      );
    } else {
      chronique = await repository.create(
        body: body,
        title: title,
        publish: publish,
        scheduledAt: scheduledAt,
        isTimeLimited: isTimeLimited,
        expiresAt: expiresAt,
      );
      state = state.copyWith(createdChroniqueId: chronique.id);
    }

    if (state.medias.isEmpty) {
      return chronique;
    }

    for (final media in List<MediaDraft>.from(state.medias)) {
      if (media.isUploaded) {
        continue;
      }
      await _uploadOne(chronique.id, media);
    }

    if (state.medias.any((item) => item.status == MediaDraftStatus.failed)) {
      throw const ApiException(message: kPartialMediaUploadMessage, statusCode: 400);
    }
    return chronique;
  }

  Future<void> _uploadOne(int chroniqueId, MediaDraft media) async {
    _replaceMedia(
      media.id,
      media.copyWith(
        status: MediaDraftStatus.uploading,
        uploadProgress: media.remoteUpload?.putCompleted == true
            ? 100
            : 0,
        clearError: true,
      ),
    );

    try {
      var current = _mediaById(media.id);
      var session = current.remoteUpload;

      if (session == null) {
        final created = await ref.read(chroniqueRepositoryProvider).createMediaUpload(
              chroniqueId: chroniqueId,
              media: current,
            );
        session = MediaDraftRemoteUpload(
          mediaId: created.media.id!,
          method: created.method,
          url: created.url,
          headers: created.headers,
          expiresAt: created.expiresAt,
          thumbnailMethod: created.thumbnailMethod,
          thumbnailUrl: created.thumbnailUrl,
          thumbnailHeaders: created.thumbnailHeaders,
          thumbnailExpiresAt: created.thumbnailExpiresAt,
        );
        current = current.copyWith(remoteUpload: session);
        _replaceMedia(current.id, current);
      }

      if (!session.putCompleted) {
        final path = current.localPath;
        final byteSize = current.byteSize;
        if (path == null || byteSize == null) {
          throw const ApiException(message: kMediaInaccessibleMessage, statusCode: 400);
        }
        await _uploadClient.putFile(
          url: session.url,
          method: session.method,
          headers: session.headers,
          localPath: path,
          byteSize: byteSize,
          onSendProgress: (sent, total) {
            final max = total > 0 ? total : byteSize;
            final percent = max <= 0 ? 0 : ((sent / max) * 100).floor().clamp(0, 100);
            final latest = _mediaById(media.id);
            _replaceMedia(
              media.id,
              latest.copyWith(
                status: MediaDraftStatus.uploading,
                uploadProgress: percent,
              ),
            );
          },
        );
        session = session.copyWith(putCompleted: true);
        current = current.copyWith(
          remoteUpload: session,
          uploadProgress: 100,
        );
        _replaceMedia(current.id, current);
      }

      await ref.read(chroniqueRepositoryProvider).completeMediaUpload(
            chroniqueId: chroniqueId,
            mediaId: session.mediaId,
          );

      await _putVideoThumbnailIfReady(media.id);

      _replaceMedia(
        media.id,
        _mediaById(media.id).copyWith(
          status: MediaDraftStatus.uploaded,
          uploadProgress: 100,
          clearError: true,
          clearRemoteUpload: true,
        ),
      );
    } catch (error) {
      final message = error is ApiException
          ? (error.message.trim().isEmpty ? kMediaUploadFailedMessage : error.message)
          : kMediaUploadFailedMessage;
      _replaceMedia(
        media.id,
        _mediaById(media.id).copyWith(
          status: MediaDraftStatus.failed,
          errorMessage: message,
        ),
      );
    }
  }

  void _startVideoThumbnail(int mediaId) {
    final generation = _draftGeneration;
    late final Future<void> task;
    task = _prepareVideoThumbnail(mediaId, generation).whenComplete(() {
      if (identical(_thumbnailTasks[mediaId], task)) {
        _thumbnailTasks.remove(mediaId);
      }
    });
    _thumbnailTasks[mediaId] = task;
  }

  Future<void> _prepareVideoThumbnail(int mediaId, int generation) async {
    MediaDraft current;
    try {
      current = _mediaById(mediaId);
    } catch (_) {
      return;
    }
    if (current.kind != MediaDraftKind.video) {
      return;
    }
    final videoPath = current.localPath?.trim();
    if (videoPath == null || videoPath.isEmpty) {
      return;
    }
    try {
      final jpegPath = await _thumbnails.extractJpeg(videoPath: videoPath);
      if (jpegPath == null || jpegPath.trim().isEmpty) {
        return;
      }
      final trimmed = jpegPath.trim();
      if (generation != _draftGeneration) {
        await _deleteThumbnailIfUnused(trimmed);
        return;
      }
      try {
        current = _mediaById(mediaId);
      } catch (_) {
        await _deleteThumbnailIfUnused(trimmed);
        return;
      }
      if (current.kind != MediaDraftKind.video) {
        await _deleteThumbnailIfUnused(trimmed);
        return;
      }
      _replaceMedia(
        mediaId,
        current.copyWith(localThumbnailPath: trimmed),
      );
    } catch (error) {
      debugPrint('[chronique-video-thumb] extract failed');
    }
  }

  Future<void> _putVideoThumbnailIfReady(int mediaId) async {
    var current = _mediaById(mediaId);
    if (current.kind != MediaDraftKind.video) {
      return;
    }
    final session = current.remoteUpload;
    final thumbUrl = session?.thumbnailUrl?.trim();
    final thumbMethod = session?.thumbnailMethod?.trim();
    if (thumbUrl == null ||
        thumbUrl.isEmpty ||
        thumbMethod == null ||
        thumbMethod.isEmpty ||
        session?.thumbnailPutCompleted == true) {
      return;
    }
    final pending = _thumbnailTasks[mediaId];
    if (pending != null) {
      await pending;
      try {
        current = _mediaById(mediaId);
      } catch (_) {
        return;
      }
    }
    final jpegPath = current.localThumbnailPath?.trim();
    if (jpegPath == null || jpegPath.isEmpty) {
      return;
    }
    try {
      final file = File(jpegPath);
      if (!file.existsSync()) {
        return;
      }
      final byteSize = file.lengthSync();
      if (byteSize < 1) {
        return;
      }
      await _uploadClient.putFile(
        url: thumbUrl,
        method: thumbMethod,
        headers: session?.thumbnailHeaders ?? const {'Content-Type': 'image/jpeg'},
        localPath: jpegPath,
        byteSize: byteSize,
      );
      try {
        current = _mediaById(mediaId);
        final remote = current.remoteUpload;
        if (remote != null) {
          _replaceMedia(
            mediaId,
            current.copyWith(
              remoteUpload: remote.copyWith(thumbnailPutCompleted: true),
            ),
          );
        }
      } catch (_) {
        // Média retiré pendant le PUT : le JPEG est quand même relâché plus bas.
      }
    } catch (error) {
      debugPrint('[chronique-video-thumb] put failed');
    } finally {
      await _releaseLocalThumbnailAfterPut(mediaId, jpegPath);
    }
  }

  Future<void> _releaseLocalThumbnailAfterPut(int mediaId, String jpegPath) async {
    try {
      final current = _mediaById(mediaId);
      final attached = current.localThumbnailPath?.trim();
      if (attached != null && attached == jpegPath.trim()) {
        _replaceMedia(mediaId, current.copyWith(clearThumbnail: true));
      }
    } catch (_) {
      // Brouillon déjà sans ce média.
    }
    await _deleteThumbnailIfUnused(jpegPath);
  }

  Set<String> _sourcePathsOf(Iterable<MediaDraft> medias) {
    return {
      for (final media in medias)
        if (media.localPath != null && media.localPath!.trim().isNotEmpty)
          media.localPath!.trim(),
    };
  }

  void _rememberUserSource(String? path) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }
    _userSourcePaths.add(trimmed);
  }

  bool _thumbnailPathIsProtected(String path, Set<String>? extraProtected) {
    if (extraProtected != null && extraProtected.contains(path)) {
      return true;
    }
    if (_userSourcePaths.contains(path)) {
      return true;
    }
    for (final media in state.medias) {
      final source = media.localPath?.trim();
      if (source != null && source == path) {
        return true;
      }
      final thumb = media.localThumbnailPath?.trim();
      if (thumb != null && thumb == path) {
        return true;
      }
    }
    return false;
  }

  Future<void> _deleteThumbnailIfUnused(
    String path, {
    Set<String>? extraProtected,
  }) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return;
    }
    for (var attempt = 0; attempt < 8; attempt++) {
      final inFlight = _thumbnailDeletes[trimmed];
      if (inFlight != null) {
        try {
          await inFlight;
        } catch (_) {
          // Une suppression concurrente a déjà signalé l’échec.
        }
        continue;
      }
      if (_thumbnailPathIsProtected(trimmed, extraProtected)) {
        return;
      }
      final pending = () async {
        try {
          await _files.deleteQuietly(
            trimmed,
            ifStillUnused: () => !_thumbnailPathIsProtected(trimmed, extraProtected),
          );
        } catch (error) {
          debugPrint('[chronique-video-thumb] temp jpeg delete failed');
        }
      }();
      _thumbnailDeletes[trimmed] = pending;
      try {
        await pending;
      } finally {
        if (identical(_thumbnailDeletes[trimmed], pending)) {
          _thumbnailDeletes.remove(trimmed);
        }
      }
      return;
    }
  }

  MediaDraft _mediaById(int id) {
    return state.medias.firstWhere((item) => item.id == id);
  }

  void _replaceMedia(int id, MediaDraft next) {
    state = state.copyWith(
      medias: [
        for (final item in state.medias)
          if (item.id == id) next else item,
      ],
    );
  }
}

final createChroniqueControllerProvider =
    AutoDisposeNotifierProvider<CreateChroniqueController, ChroniqueDraft>(
  CreateChroniqueController.new,
);

