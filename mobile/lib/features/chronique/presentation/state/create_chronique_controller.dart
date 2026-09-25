import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../media/chronique_local_file_access.dart';
import '../../media/chronique_local_media_picker.dart';
import '../../media/chronique_media_limits.dart';
import '../../media/chronique_media_mime.dart';
import '../../models/chronique.dart';
import '../../models/chronique_draft.dart';
import '../../models/chronique_media_upload.dart';
import '../../models/media_draft.dart';
import '../../providers/chronique_providers.dart';
import '../../services/chronique_media_upload_client.dart';

/// Brouillon local (texte + médias) + pipeline create → URL signée → PUT R2 → complete.
class CreateChroniqueController extends AutoDisposeNotifier<ChroniqueDraft> {
  int _nextMediaId = 0;

  ChroniqueLocalMediaPicker get _picker =>
      ref.read(chroniqueLocalMediaPickerProvider);

  ChroniqueLocalFileAccess get _files =>
      ref.read(chroniqueLocalFileAccessProvider);

  ChroniqueMediaUploadClient get _uploadClient =>
      ref.read(chroniqueMediaUploadClientProvider);

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
    String? contentType,
    MediaDraftStatus status = MediaDraftStatus.selected,
  }) {
    _nextMediaId += 1;
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
          contentType: contentType,
          status: status,
        ),
      ],
    );
  }

  void removeMediaDraft(int id) {
    state = state.copyWith(
      medias: [
        for (final media in state.medias)
          if (media.id != id) media,
      ],
    );
  }

  void clearDraft() {
    _nextMediaId = 0;
    state = const ChroniqueDraft();
  }

  Future<String?> pickImage() => _pick(_picker.pickImage);

  Future<String?> pickVideo() => _pick(_picker.pickVideo);

  Future<String?> pickAudio() => _pick(_picker.pickAudio);

  Future<String?> pickDocument() => _pick(_picker.pickDocument);

  Future<String?> _pick(Future<MediaPickResult> Function() pick) async {
    final result = await pick();
    switch (result) {
      case MediaPickCancelled():
        return null;
      case MediaPickFailed(:final message):
        return message;
      case MediaPickSelected(
          :final kind,
          :final sourceType,
          :final fileName,
          :final byteSize,
          :final localPath,
          :final contentType,
          :final platformMime,
        ):
        final mime = contentType ??
            resolveChroniqueMediaContentType(
              kind: kind,
              fileName: fileName,
              localPath: localPath,
              platformMime: platformMime,
            );
        if (mime == null) {
          return kMediaUnsupportedMessage;
        }
        addMediaDraft(
          kind: kind,
          sourceType: sourceType,
          fileName: fileName,
          byteSize: byteSize,
          localPath: localPath,
          contentType: mime,
        );
        return null;
    }
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

