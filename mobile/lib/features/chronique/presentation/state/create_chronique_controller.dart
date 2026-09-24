import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../media/chronique_local_media_picker.dart';
import '../../models/chronique.dart';
import '../../models/chronique_draft.dart';
import '../../models/media_draft.dart';
import '../../providers/chronique_providers.dart';

/// Brouillon local (texte + médias). La publication HTTP reste texte seul.
class CreateChroniqueController extends AutoDisposeNotifier<ChroniqueDraft> {
  int _nextMediaId = 0;

  ChroniqueLocalMediaPicker get _picker =>
      ref.read(chroniqueLocalMediaPickerProvider);

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
        ):
        addMediaDraft(
          kind: kind,
          sourceType: sourceType,
          fileName: fileName,
          byteSize: byteSize,
          localPath: localPath,
        );
        return null;
    }
  }

  /// `POST /chroniques` immédiat. Les médias locaux ne partent pas dans ce lot.
  Future<Chronique> publish({
    required String body,
    String? title,
  }) {
    return ref.read(chroniqueRepositoryProvider).create(
          body: body,
          title: title,
        );
  }
}

final createChroniqueControllerProvider =
    AutoDisposeNotifierProvider<CreateChroniqueController, ChroniqueDraft>(
  CreateChroniqueController.new,
);
