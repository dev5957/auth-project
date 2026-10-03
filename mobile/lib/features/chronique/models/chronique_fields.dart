/// Limites alignées sur `chroniqueFields.js` (points de code, après trim).
abstract final class ChroniqueFields {
  static const int bodyMinNonWhitespace = 10;
  static const int bodyMax = 1000;
  static const int titleMax = 200;

  static final RegExp _whitespace = RegExp(r'\s', unicode: true);

  static int runeLength(String value) => value.runes.length;

  static int nonWhitespaceLength(String value) {
    return runeLength(value.replaceAll(_whitespace, ''));
  }

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
    if (nonWhitespaceLength(body) < bodyMinNonWhitespace) {
      return 'Le texte doit contenir au moins 10 caractères';
    }
    if (runeLength(body) > bodyMax) {
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
