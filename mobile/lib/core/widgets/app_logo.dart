import 'package:flutter/material.dart';

import '../branding/app_brand.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

/// Placeholder logo Lumina. Remplacer l’intérieur plus tard, pas les call sites.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 72,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Semantics(
      label: AppBrand.appName,
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(AppSpacing.lg),
          ),
          child: Center(
            child: Text(
              AppBrand.appName[0],
              style: AppTextTheme.display.copyWith(color: colors.textOnPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
