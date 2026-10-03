/// Limites alignées sur `communityFields.js` (points de code, après trim).
abstract final class CommunityFields {
  static const int nameMin = 10;
  static const int nameMax = 100;
  static const int descriptionMax = 500;
  static const int searchQueryMax = 100;

  static int runeLength(String value) => value.runes.length;

  static String trimmedName(String raw) => raw.trim();

  static String? trimmedDescription(String raw) {
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  static String? nameError(String raw) {
    final name = trimmedName(raw);
    if (name.isEmpty) {
      return 'Le nom est obligatoire';
    }
    final length = runeLength(name);
    if (length < nameMin) {
      return 'Le nom doit contenir au moins 10 caractères';
    }
    if (length > nameMax) {
      return 'Le nom est trop long';
    }
    return null;
  }

  static String? descriptionError(String raw) {
    final description = raw.trim();
    if (description.isEmpty) {
      return null;
    }
    if (runeLength(description) > descriptionMax) {
      return 'La description est trop longue';
    }
    return null;
  }

  /// `q` de `GET /communities/search` (trim + max 100 points de code).
  static String? searchQueryError(String raw) {
    final query = raw.trim();
    if (query.isEmpty) {
      return 'Saisissez un nom de communauté';
    }
    if (runeLength(query) > searchQueryMax) {
      return 'Le nom recherché est trop long';
    }
    return null;
  }
}

enum UserSearchMode { login, phone }

/// Validation locale de `GET /users/search` (login XOR phone, trim, max login 64).
abstract final class UserSearchFields {
  static const int loginMax = 64;

  static String preparedLogin(String raw) => raw.trim().toLowerCase();

  static String preparedPhone(String raw) => raw.trim();

  static String? loginError(String raw) {
    final login = preparedLogin(raw);
    if (login.isEmpty) {
      return 'Saisissez un login';
    }
    if (CommunityFields.runeLength(login) > loginMax) {
      return 'Le login est invalide';
    }
    return null;
  }

  static String? phoneError(String raw) {
    if (preparedPhone(raw).isEmpty) {
      return 'Saisissez un numéro de téléphone';
    }
    return null;
  }

  static String? errorFor(UserSearchMode mode, String raw) {
    return switch (mode) {
      UserSearchMode.login => loginError(raw),
      UserSearchMode.phone => phoneError(raw),
    };
  }
}
