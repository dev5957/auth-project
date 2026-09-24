/// Limites alignées sur `chroniqueFields.js` (code points, après trim).
abstract final class ChroniqueFields {
  static const int bodyMin = 20;
  static const int bodyMax = 5000;
  static const int titleMax = 200;

  static int runeLength(String value) => value.runes.length;

  static String trimmedBody(String raw) => raw.trim();

  static String? trimmedTitle(String raw) {
    final title = raw.trim();
    return title.isEmpty ? null : title;
  }

  static String? bodyError(String raw) {
    final body = trimmedBody(raw);
    if (body.isEmpty) {
      return 'Le texte est obligatoire';
    }
    final length = runeLength(body);
    if (length < bodyMin) {
      return 'Le texte doit contenir au moins 20 caractères';
    }
    if (length > bodyMax) {
      return 'Le texte est trop long';
    }
    return null;
  }

  static String? titleError(String raw) {
    final title = raw.trim();
    if (title.isEmpty) {
      return null;
    }
    if (runeLength(title) > titleMax) {
      return 'Le titre est trop long';
    }
    return null;
  }

  static bool canPublishBody(String raw) => bodyError(raw) == null;

  static String excerpt(String raw, {int maxRunes = 140}) {
    final body = trimmedBody(raw);
    if (runeLength(body) <= maxRunes) {
      return body;
    }
    return '${String.fromCharCodes(body.runes.take(maxRunes))}…';
  }
}
