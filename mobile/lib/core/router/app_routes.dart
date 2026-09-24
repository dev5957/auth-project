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

  /// Lecture d’une chronique. `:chroniqueId` numérique.
  static const String exploreDetail = '/explore/:chroniqueId';

  /// Édition d’une chronique existante.
  static const String exploreEdit = '/explore/:chroniqueId/edit';

  /// Archives volontaires.
  static const String archives = '/archives';

  /// Publications programmées.
  static const String upcoming = '/upcoming';

  static String chroniqueDetail(int id) => '/explore/$id';

  static String chroniqueEdit(int id) => '/explore/$id/edit';

  static final RegExp _exploreDetailLocation = RegExp(r'^/explore/\d+$');
  static final RegExp _exploreEditLocation = RegExp(r'^/explore/\d+/edit$');

  static bool isAuthenticatedLocation(String location) {
    return location == home ||
        location == create ||
        location == explore ||
        location == archives ||
        location == upcoming ||
        _exploreDetailLocation.hasMatch(location) ||
        _exploreEditLocation.hasMatch(location);
  }
}
