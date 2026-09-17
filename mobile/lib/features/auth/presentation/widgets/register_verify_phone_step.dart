import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';

/// Placeholder Step 4 — OTP complet plus tard.
class RegisterVerifyPhoneStep extends StatelessWidget {
  const RegisterVerifyPhoneStep({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Verify your phone',
          textAlign: TextAlign.center,
          style: AppTextTheme.titleLarge.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Step 4 of 4 · Verify',
          textAlign: TextAlign.center,
          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'A verification code was sent. Entering the code will be available in the next step.',
          textAlign: TextAlign.center,
          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}
