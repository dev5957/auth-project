import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/community.dart';
import 'community_media_placeholder.dart';

class CommunityHeader extends StatelessWidget {
  const CommunityHeader({super.key, required this.community});

  final Community community;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.md, AppSpacing.xxl, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CommunityMediaPlaceholder(label: 'Bannière', height: 72),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(
                width: 56,
                child: CommunityMediaPlaceholder(label: 'Avatar', height: 56),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      community.name,
                      key: const ValueKey('community-detail-name'),
                      style: AppTextTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      community.myRole.label,
                      key: const ValueKey('community-detail-role'),
                      style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
