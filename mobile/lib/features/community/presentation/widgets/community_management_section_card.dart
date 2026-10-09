import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';

class CommunityManagementSectionCard extends StatelessWidget {
  const CommunityManagementSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.titleKey,
  });

  final String title;
  final Widget child;
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Material(
        color: colors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.xxxl),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: colors.border),
          child: ExpansionTile(
            initiallyExpanded: false,
            tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              0,
              AppSpacing.xxl,
              AppSpacing.xxl,
            ),
            title: Text(
              title,
              key: titleKey,
              style: AppTextTheme.titleMedium,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
