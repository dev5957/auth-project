import 'media_draft.dart';

/// Brouillon local de création. Distinct du JSON API [Chronique].
class ChroniqueDraft {
  const ChroniqueDraft({
    this.title = '',
    this.body = '',
    this.medias = const [],
  });

  final String title;
  final String body;
  final List<MediaDraft> medias;

  ChroniqueDraft copyWith({
    String? title,
    String? body,
    List<MediaDraft>? medias,
  }) {
    return ChroniqueDraft(
      title: title ?? this.title,
      body: body ?? this.body,
      medias: medias ?? this.medias,
    );
  }
}
