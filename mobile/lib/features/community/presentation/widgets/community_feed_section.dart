import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../chronique/presentation/widgets/chronique_card.dart';
import '../../../chronique/presentation/widgets/chronique_media_viewer.dart';
import '../../models/community.dart';
import '../state/community_feed_controller.dart';
import 'community_publication_social_bar.dart';

class CommunityFeedSection extends ConsumerWidget {
  const CommunityFeedSection({
    super.key,
    required this.community,
  });

  final Community community;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final state = ref.watch(communityFeedControllerProvider(community.id));
    return ListView(
      key: const ValueKey('community-feed-scroll'),
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.md, AppSpacing.xxl, AppSpacing.xxl),
      children: [
        Material(
          color: colors.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.lg),
            side: BorderSide(color: colors.border),
          ),
          child: InkWell(
            key: const ValueKey('community-publish-open'),
            onTap: () => context.push(
              AppRoutes.communityPublicationCreate(community.id),
              extra: community.name,
            ),
            borderRadius: BorderRadius.circular(AppSpacing.lg),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, color: colors.textSecondary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Exprimez-vous dans la communauté…',
                      style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text('Publications', style: AppTextTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        switch (state) {
          CommunityFeedLoading() => const AppLoading(),
          CommunityFeedError(:final message) => Text(message, key: const ValueKey('community-feed-error')),
          CommunityFeedReady(:final items) => items.isEmpty
              ? Text(
                  'Aucune publication pour le moment',
                  key: const ValueKey('community-feed-empty'),
                  style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                )
              : Column(
                  children: [
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.author.displayLabel,
                              style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            ChroniqueCard(
                              key: ValueKey('community-feed-item-${item.id}'),
                              chronique: item.asChronique(),
                              showFeedMedia: true,
                              menuEnabled: false,
                              onTap: () => context.push(
                                AppRoutes.communityPublicationDetail(community.id, item.id),
                              ),
                              onMediaSelected: (media) =>
                                  openChroniqueFeedMedia(context, media),
                            ),
                            CommunityPublicationSocialBar(
                              publication: item,
                              onLike: () async {
                                final ok = await ref
                                    .read(communityFeedControllerProvider(community.id).notifier)
                                    .toggleLike(item);
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Impossible de mettre à jour le j’aime')),
                                  );
                                }
                              },
                              onComments: () => context.push(
                                AppRoutes.communityPublicationDetail(community.id, item.id),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        },
      ],
    );
  }
}
