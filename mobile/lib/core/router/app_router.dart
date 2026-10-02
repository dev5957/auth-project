import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/auth_entry_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/oauth_complete_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/signup_method_screen.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/auth/state/auth_state.dart';
import '../../features/chronique/models/chronique.dart';
import '../../features/chronique/presentation/screens/archives_screen.dart';
import '../../features/chronique/presentation/screens/chronique_detail_screen.dart';
import '../../features/chronique/presentation/screens/create_chronique_screen.dart';
import '../../features/chronique/presentation/screens/edit_chronique_screen.dart';
import '../../features/chronique/presentation/screens/expired_chroniques_screen.dart';
import '../../features/chronique/presentation/screens/mon_fil_screen.dart';
import '../../features/chronique/presentation/screens/upcoming_chroniques_screen.dart';
import '../../features/community/presentation/screens/community_detail_screen.dart';
import '../../features/community/presentation/screens/community_list_screen.dart';
import '../../features/community/presentation/screens/community_search_screen.dart';
import '../../features/community/presentation/screens/create_community_screen.dart';
import '../../features/community/presentation/screens/invitation_inbox_screen.dart';
import '../../features/community/presentation/screens/user_search_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import 'app_routes.dart';
import 'session_splash_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<AuthState>(
    authControllerProvider,
    (previous, next) {
      debugPrint(
        '[auth-restore-diag] auth listen previous=${previous.runtimeType} next=${next.runtimeType}',
      );
      refresh.value++;
    },
    fireImmediately: true,
  );
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      String? target;
      if (auth is AuthLoading) {
        final onLoginFlow = location == AppRoutes.login ||
            location == AppRoutes.forgotPassword ||
            location == AppRoutes.registerChoose ||
            location == AppRoutes.register ||
            location == AppRoutes.oauthComplete;
        if (onLoginFlow || location == AppRoutes.splash) {
          target = null;
        } else {
          target = AppRoutes.splash;
        }
      } else if (auth is AuthAuthenticated) {
        target = AppRoutes.isAuthenticatedLocation(location)
            ? null
            : AppRoutes.home;
      } else if (location == AppRoutes.splash) {
        // Cas 1 / 5 : premier lancement ou refresh invalide au cold start → carousel.
        target = AppRoutes.entry;
      } else if (AppRoutes.isAuthenticatedLocation(location)) {
        // Cas 4 : logout (ou session tombée pendant Home / CREATE / EXPLORE / détail) → Login.
        target = AppRoutes.login;
      } else {
        // Cas 2 : /auth/login (ou register / carousel) reste en place.
        target = null;
      }
      debugPrint(
        '[auth-restore-diag] GoRouter redirect auth=${auth.runtimeType} '
        'from=$location to=${target ?? '(stay)'}',
      );
      debugPrint(
        '[auth-login-diag] GoRouter redirect location=$location '
        'auth=${auth.runtimeType} destination=${target ?? '(stay)'}',
      );
      return target;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SessionSplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.entry,
        builder: (context, state) => const AuthEntryScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.registerChoose,
        builder: (context, state) => const SignupMethodScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.oauthComplete,
        builder: (context, state) => const OAuthCompleteScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.create,
        pageBuilder: (context, state) => MaterialPage<void>(
          key: state.pageKey,
          fullscreenDialog: true,
          child: const CreateChroniqueScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.explore,
        builder: (context, state) => const MonFilScreen(),
      ),
      GoRoute(
        path: AppRoutes.archives,
        builder: (context, state) => const ArchivesScreen(),
      ),
      GoRoute(
        path: AppRoutes.expired,
        builder: (context, state) => const ExpiredChroniquesScreen(),
      ),
      GoRoute(
        path: AppRoutes.upcoming,
        builder: (context, state) => const UpcomingChroniquesScreen(),
      ),
      GoRoute(
        path: AppRoutes.invitations,
        builder: (context, state) => const InvitationInboxScreen(),
      ),
      GoRoute(
        path: AppRoutes.communitiesCreate,
        builder: (context, state) => const CreateCommunityScreen(),
      ),
      GoRoute(
        path: AppRoutes.communitiesSearch,
        builder: (context, state) => const CommunitySearchScreen(),
      ),
      GoRoute(
        path: AppRoutes.communityInviteSearchPath,
        builder: (context, state) {
          final rawId = state.pathParameters['communityId'];
          final id = int.tryParse(rawId ?? '') ?? 0;
          return UserSearchScreen(communityId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.communityDetailPath,
        builder: (context, state) {
          final rawId = state.pathParameters['communityId'];
          final id = int.tryParse(rawId ?? '') ?? 0;
          return CommunityDetailScreen(communityId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.communities,
        builder: (context, state) => const CommunityListScreen(),
      ),
      GoRoute(
        path: AppRoutes.exploreEdit,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! Chronique) {
            return const Scaffold(
              body: Center(child: Text('Chronique introuvable')),
            );
          }
          return EditChroniqueScreen(chronique: extra);
        },
      ),
      GoRoute(
        path: AppRoutes.exploreDetail,
        builder: (context, state) {
          final rawId = state.pathParameters['chroniqueId'];
          final id = int.tryParse(rawId ?? '');
          final extra = state.extra;
          return ChroniqueDetailScreen(
            chroniqueId: id,
            chronique: extra is Chronique ? extra : null,
          );
        },
      ),
    ],
  );
});
