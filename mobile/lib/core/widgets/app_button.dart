import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

enum AppButtonVariant { primary, secondary }

/// Bouton Lumina (Sign in, Sign up, Verify).
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.variant = AppButtonVariant.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final AppButtonVariant variant;

  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final enabled = onPressed != null && !isLoading;
    final isPrimary = variant == AppButtonVariant.primary;

    final background = isPrimary ? colors.primary : colors.bgSurface;
    final foreground = isPrimary ? colors.textOnPrimary : colors.primary;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: Material(
        color: enabled ? background : background.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.lg),
          side: BorderSide(color: enabled ? colors.primary : colors.primary.withValues(alpha: 0.5)),
        ),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(AppSpacing.lg),
          splashColor: colors.primaryPressed.withValues(alpha: 0.24),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: AppSpacing.xxl,
                    height: AppSpacing.xxl,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                : Text(
                    label,
                    style: AppTextTheme.labelLarge.copyWith(color: foreground),
                  ),
          ),
        ),
      ),
    );
  }
}
