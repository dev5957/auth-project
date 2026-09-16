import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/branding/app_brand.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_logo.dart';

/// Porte d’entrée Auth. Pas de logique métier ici.
class AuthEntryScreen extends StatelessWidget {
  const AuthEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Column(
            children: [
              const Spacer(flex: 2),
              const AppLogo(size: 88),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'Welcome to ${AppBrand.appName}',
                textAlign: TextAlign.center,
                style: AppTextTheme.display.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Create an account or sign in to continue.',
                textAlign: TextAlign.center,
                style: AppTextTheme.bodyLarge.copyWith(color: colors.textSecondary),
              ),
              const Spacer(flex: 3),
              AppButton(
                label: 'Get Started',
                onPressed: () => context.push(AppRoutes.register),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Sign in',
                variant: AppButtonVariant.secondary,
                onPressed: () => context.push(AppRoutes.login),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
