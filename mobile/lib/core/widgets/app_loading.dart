import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

/// Indicateur de chargement Lumina (session, réseau, OTP).
class AppLoading extends StatelessWidget {
  const AppLoading({
    super.key,
    this.message,
  });

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: AppSpacing.xxxl,
            height: AppSpacing.xxxl,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: colors.primary,
            ),
          ),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
