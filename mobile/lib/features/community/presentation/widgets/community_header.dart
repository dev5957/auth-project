import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/community.dart';
import 'community_avatar.dart';
import 'community_banner.dart';

class CommunityHeader extends StatelessWidget {
  const CommunityHeader({
    super.key,
    required this.community,
    this.onEditAvatar,
    this.onEditBanner,
  });

  final Community community;
  final VoidCallback? onEditAvatar;
  final VoidCallback? onEditBanner;

  static const double bannerHeight = 140;
  static const double avatarSize = 88;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    const overlap = avatarSize / 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: bannerHeight + overlap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: bannerHeight,
                child: CommunityBanner(
                  readUrl: community.bannerReadUrl,
                  height: bannerHeight,
                  onEdit: onEditBanner,
                ),
              ),
              Positioned(
                top: bannerHeight - overlap,
                left: 0,
                right: 0,
                child: Center(
                  child: CommunityAvatar(
                    readUrl: community.avatarReadUrl,
                    size: avatarSize,
                    onEdit: onEditAvatar,
                    heroTag: 'community-avatar-${community.id}',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.sm),
          child: Column(
            children: [
              Text(
                community.name,
                key: const ValueKey('community-detail-name'),
                textAlign: TextAlign.center,
                style: AppTextTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                community.myRole.label,
                key: const ValueKey('community-detail-role'),
                textAlign: TextAlign.center,
                style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
