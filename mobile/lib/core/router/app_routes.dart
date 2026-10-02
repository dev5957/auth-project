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

  /// Chroniques éphémères expirées (rétention).
  static const String expired = '/expired';

  /// Publications programmées.
  static const String upcoming = '/upcoming';

  /// Liste des communautés dont l’utilisateur est membre.
  static const String communities = '/communities';

  /// Création d’une communauté.
  static const String communitiesCreate = '/communities/create';

  /// Recherche de communautés par nom (aperçu limité).
  static const String communitiesSearch = '/communities/search';

  /// Détail d’une communauté. `:communityId` numérique.
  static const String communityDetailPath = '/communities/:communityId';

  /// Recherche d’un utilisateur à inviter (propriétaire).
  static const String communityInviteSearchPath = '/communities/:communityId/invite';

  static String chroniqueDetail(int id) => '/explore/$id';

  static String chroniqueEdit(int id) => '/explore/$id/edit';

  static String communityDetail(int id) => '/communities/$id';

  static String communityInviteSearch(int id) => '/communities/$id/invite';

  static final RegExp _exploreDetailLocation = RegExp(r'^/explore/\d+$');
  static final RegExp _exploreEditLocation = RegExp(r'^/explore/\d+/edit$');
  static final RegExp _communityDetailLocation = RegExp(r'^/communities/\d+$');
  static final RegExp _communityInviteLocation = RegExp(r'^/communities/\d+/invite$');

  static bool isAuthenticatedLocation(String location) {
    return location == home ||
        location == create ||
        location == explore ||
        location == archives ||
        location == expired ||
        location == upcoming ||
        location == communities ||
        location == communitiesCreate ||
        location == communitiesSearch ||
        _exploreDetailLocation.hasMatch(location) ||
        _exploreEditLocation.hasMatch(location) ||
        _communityInviteLocation.hasMatch(location) ||
        _communityDetailLocation.hasMatch(location);
  }
}
