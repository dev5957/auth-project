import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_card.dart';

/// Emplacement V1 pour le contenu futur (profil, modules).
class HomeSpaceCard extends StatelessWidget {
  const HomeSpaceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your space',
            style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Everything is ready.',
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
