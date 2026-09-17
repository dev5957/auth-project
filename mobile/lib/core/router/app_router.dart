import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/auth_entry_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/auth/state/auth_state.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import 'app_routes.dart';
import 'session_splash_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<AuthState>(
    authControllerProvider,
    (_, __) {
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
        final onLoginFlow = location == AppRoutes.login || location == AppRoutes.register;
        if (onLoginFlow || location == AppRoutes.splash) {
          target = null;
        } else {
          target = AppRoutes.splash;
        }
      } else if (auth is AuthAuthenticated) {
        target = location == AppRoutes.home ? null : AppRoutes.home;
      } else if (location == AppRoutes.splash || location == AppRoutes.home) {
        target = AppRoutes.entry;
      } else {
        target = null;
      }
      debugPrint(
        '[auth-http-diag][B] GoRouter redirect auth=${auth.runtimeType} '
        'from=$location to=${target ?? '(stay)'}',
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
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );
});
