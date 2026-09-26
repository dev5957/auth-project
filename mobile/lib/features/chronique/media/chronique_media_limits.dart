import '../models/media_draft.dart';

/// Quotas UX alignés sur le backend (`MAX_MEDIA` / `MAX_BYTES`). Le serveur reste la source de vérité.
const int kChroniqueMaxMediaCount = 5;
const int kChroniqueMaxMediaBytes = 209715200;

const String kTooManyMediaMessage = 'Maximum 5 médias';
const String kMediaLimitReachedMessage = 'Limite de 5 médias atteinte';
const String kSomeMediaSkippedLimitMessage =
    'Certains fichiers n\'ont pas été ajoutés : maximum 5 médias';
const String kMediaQuotaExceededMessage = 'La taille totale des médias dépasse 200 Mo';
const String kMediaUploadFailedMessage = 'L\'envoi du média a échoué';
const String kPartialMediaUploadMessage = 'Certains médias n\'ont pas pu être envoyés';

/// Total actuel des tailles renseignées (octets). Les médias sans taille comptent 0.
int chroniqueDraftMediaBytes(Iterable<MediaDraft> medias) {
  var bytes = 0;
  for (final media in medias) {
    bytes += media.byteSize ?? 0;
  }
  return bytes;
}

/// Erreur bloquante dérivée uniquement de la liste courante (jamais d’un cache).
String? chroniqueDraftMediaError(Iterable<MediaDraft> medias) {
  var count = 0;
  var bytes = 0;
  for (final media in medias) {
    count += 1;
    bytes += media.byteSize ?? 0;
  }
  if (count > kChroniqueMaxMediaCount) {
    return kTooManyMediaMessage;
  }
  if (bytes > kChroniqueMaxMediaBytes) {
    return kMediaQuotaExceededMessage;
  }
  return null;
}

bool isChroniqueMediaFormMessage(String? message) {
  return message == kTooManyMediaMessage ||
      message == kMediaLimitReachedMessage ||
      message == kSomeMediaSkippedLimitMessage ||
      message == kMediaQuotaExceededMessage;
}
