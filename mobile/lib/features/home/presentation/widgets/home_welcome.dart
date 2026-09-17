import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';

/// Salutation et login issus de [AuthAuthenticated], sans requête.
class HomeWelcome extends StatelessWidget {
  const HomeWelcome({
    super.key,
    required this.login,
  });

  final String login;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome back',
          style: AppTextTheme.titleLarge.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          login,
          style: AppTextTheme.display.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Session active',
          style: AppTextTheme.labelSmall.copyWith(color: colors.success),
        ),
      ],
    );
  }
}
