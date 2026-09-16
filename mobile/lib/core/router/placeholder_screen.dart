import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

/// Écran temporaire de route. Pas un écran métier.
class RouterPlaceholderScreen extends StatelessWidget {
  const RouterPlaceholderScreen({
    super.key,
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        foregroundColor: colors.textPrimary,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
          ),
        ),
      ),
    );
  }
}
