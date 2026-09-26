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
