import 'package:flutter/material.dart';

import '../../../../core/branding/app_brand.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_logo.dart';
import '../home_user_initials.dart';

/// Bandeau Home : identité Lumina + initiales du login Auth.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.login,
  });

  final String login;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final initials = homeUserInitials(login);
    return Row(
      children: [
        const AppLogo(size: 40),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppBrand.appName,
                style: AppTextTheme.titleSmall.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Your home',
                style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        if (initials.isNotEmpty)
          Semantics(
            label: login,
            child: CircleAvatar(
              radius: 24,
              backgroundColor: colors.bgRaised,
              foregroundColor: colors.primary,
              child: Text(
                initials,
                style: AppTextTheme.labelLarge.copyWith(color: colors.primary),
              ),
            ),
          ),
      ],
    );
  }
}
