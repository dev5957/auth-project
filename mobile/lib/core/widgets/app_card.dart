import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Surface Lumina pour les futurs écrans Auth.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.xxxl),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.xxl),
        child: child,
      ),
    );
  }
}
