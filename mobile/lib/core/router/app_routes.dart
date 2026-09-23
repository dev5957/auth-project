/// Chemins GoRouter Lumina. Les redirects session sont dans [appRouterProvider].
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String entry = '/';
  static const String login = '/auth/login';
  static const String forgotPassword = '/auth/forgot-password';
  static const String registerChoose = '/auth/register/choose';
  static const String register = '/auth/register';
  static const String oauthComplete = '/auth/oauth/complete';
  static const String home = '/home';

  /// Assistant de création (modal plein écran) — Lot création texte.
  static const String create = '/create';

  /// Fil personnel « Mon Fil ». Route technique conservée.
  static const String explore = '/explore';

  static bool isAuthenticatedLocation(String location) {
    return location == home || location == create || location == explore;
  }
}
