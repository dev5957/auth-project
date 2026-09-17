import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/auth_entry_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/auth/state/auth_state.dart';
import 'app_routes.dart';
import 'placeholder_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<AuthState>(authControllerProvider, (_, __) {
    refresh.value++;
  });
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.entry,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      final onGuestRoute = location == AppRoutes.entry ||
          location == AppRoutes.login ||
          location == AppRoutes.register;
      if (auth is AuthLoading) {
        return null;
      }
      if (auth is AuthAuthenticated && onGuestRoute) {
        return AppRoutes.home;
      }
      if (auth is AuthUnauthenticated && location == AppRoutes.home) {
        return AppRoutes.entry;
      }
      return null;
    },
    routes: [
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
        builder: (context, state) => const RouterPlaceholderScreen(title: 'Home placeholder'),
      ),
    ],
  );
});
