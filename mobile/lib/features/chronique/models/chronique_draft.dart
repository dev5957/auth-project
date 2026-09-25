import 'media_draft.dart';

/// Brouillon local de création. Distinct du JSON API [Chronique].
class ChroniqueDraft {
  const ChroniqueDraft({
    this.title = '',
    this.body = '',
    this.medias = const [],
    this.createdChroniqueId,
  });

  final String title;
  final String body;
  final List<MediaDraft> medias;

  /// Renseigné après `POST /chroniques` réussi, pour ne pas recréer à un retry média.
  final int? createdChroniqueId;

  ChroniqueDraft copyWith({
    String? title,
    String? body,
    List<MediaDraft>? medias,
    int? createdChroniqueId,
    bool clearCreatedChroniqueId = false,
  }) {
    return ChroniqueDraft(
      title: title ?? this.title,
      body: body ?? this.body,
      medias: medias ?? this.medias,
      createdChroniqueId: clearCreatedChroniqueId
          ? null
          : (createdChroniqueId ?? this.createdChroniqueId),
    );
  }
}
