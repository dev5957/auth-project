import 'chronique.dart';
import 'chronique_date.dart';

/// UX uniquement. Le backend reste l’autorité (`published_at + 30 min`, `>=` fermé).
const Duration kChroniqueCorrectionWindow = Duration(minutes: 30);

const String kCorrectionWindowExpiredCode = 'correction_window_expired';
const String kCorrectionWindowExpiredUserMessage =
    'La période de modification est terminée.';

/// `true` tant que `now < published_at + 30:00.000`. Scheduled : pas de fenêtre.
bool isChroniqueTextCorrectionOpen(Chronique chronique, {DateTime? now}) {
  if (chronique.status == 'scheduled') {
    return true;
  }
  if (chronique.status != 'active') {
    return false;
  }
  final published = ChroniqueDateHelper.tryParse(chronique.publishedAt);
  if (published == null) {
    return true;
  }
  final clock = now ?? DateTime.now();
  final deadline = published.add(kChroniqueCorrectionWindow);
  return clock.isBefore(deadline);
}
