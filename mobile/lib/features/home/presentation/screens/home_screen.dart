import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../auth/providers/auth_controller.dart';
import '../../../auth/state/auth_state.dart';
import '../widgets/home_create_explore_actions.dart';
import '../widgets/home_header.dart';
import '../widgets/home_space_card.dart';
import '../widgets/home_user_menu.dart';
import '../widgets/home_welcome.dart';

/// Home authentifié V1. Données : [AuthAuthenticated.user] uniquement.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    if (_loggingOut) {
      return;
    }
    setState(() => _loggingOut = true);
    try {
      await ref.read(authControllerProvider.notifier).logout();
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  Future<void> _openUserMenu() async {
    if (_loggingOut) {
      return;
    }
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      return;
    }
    await showHomeUserMenu(
      context,
      login: auth.user.login,
      onUpcoming: () {
        if (!mounted) {
          return;
        }
        context.push(AppRoutes.upcoming);
      },
      onArchives: () {
        if (!mounted) {
          return;
        }
        context.push(AppRoutes.archives);
      },
      onLogout: _logout,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      return Scaffold(
        backgroundColor: colors.bgBase,
        body: const SafeArea(child: AppLoading()),
      );
    }

    final login = auth.user.login;
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    HomeHeader(
                      login: login,
                      onAvatarTap: _loggingOut ? null : _openUserMenu,
                    ),
                    const SizedBox(height: AppSpacing.xxxl),
                    HomeWelcome(login: login),
                    const SizedBox(height: AppSpacing.xxxl),
                    const HomeCreateExploreActions(),
                    const SizedBox(height: AppSpacing.xxxl),
                    const HomeSpaceCard(),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
