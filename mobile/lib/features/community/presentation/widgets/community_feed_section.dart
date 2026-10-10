import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../auth/providers/auth_controller.dart';
import '../../../auth/state/auth_state.dart';
import '../../../chronique/models/chronique.dart';
import '../../../chronique/presentation/widgets/chronique_card.dart';
import '../../../chronique/presentation/widgets/chronique_media_viewer.dart';
import '../../models/community.dart';
import '../../models/community_publication.dart';
import '../../providers/community_providers.dart';
import '../state/community_feed_controller.dart';
import '../state/community_publication_sync.dart';
import 'community_comments_sheet.dart';
import 'community_publication_social_bar.dart';

class CommunityFeedSection extends ConsumerStatefulWidget {
  const CommunityFeedSection({
    super.key,
    required this.community,
  });

  final Community community;

  @override
  ConsumerState<CommunityFeedSection> createState() => _CommunityFeedSectionState();
}

class _CommunityFeedSectionState extends ConsumerState<CommunityFeedSection> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int? get _viewerId {
    final auth = ref.read(authControllerProvider);
    if (auth is AuthAuthenticated) {
      return auth.user.id;
    }
    return null;
  }

  bool _isAuthor(CommunityPublication item) {
    final viewerId = _viewerId;
    return viewerId != null && item.author.userId == viewerId;
  }

  bool _canModeratorDelete(CommunityPublication item) {
    final role = widget.community.myRole;
    if (role != CommunityRole.owner && role != CommunityRole.admin) {
      return false;
    }
    if (item.status != 'active') {
      return false;
    }
    return !_isAuthor(item);
  }

  void _openAuthorDetail(CommunityPublication item) {
    context.push(AppRoutes.communityPublicationDetail(widget.community.id, item.id));
  }

  Future<void> _confirmModeratorDelete(CommunityPublication item) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la publication ?'),
        content: const Text('Elle disparaîtra du fil.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(communityRepositoryProvider).deletePublication(
            communityId: widget.community.id,
            publicationId: item.id,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Publication supprimée')),
      );
      await ref.read(communityFeedControllerProvider(widget.community.id).notifier).load();
    } on ApiException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de supprimer la publication')),
      );
    }
  }

  void _openMedia(BuildContext context, ChroniqueMedia media) {
    FocusManager.instance.primaryFocus?.unfocus();
    openChroniqueFeedMedia(context, media);
  }

  Future<void> _openComments(CommunityPublication item) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final viewerId = _viewerId;
    await showCommunityCommentsSheet(
      context: context,
      community: widget.community,
      publication: item,
      isPublicationAuthor: viewerId != null && item.author.userId == viewerId,
      onCountDelta: (delta) {
        var base = item.commentCount;
        final feed = ref.read(communityFeedControllerProvider(widget.community.id));
        if (feed is CommunityFeedReady) {
          for (final candidate in feed.items) {
            if (candidate.id == item.id) {
              base = candidate.commentCount;
              break;
            }
          }
        }
        final nextCount = (base + delta).clamp(0, 1 << 30);
        final patch = CommunityPublicationInteractionPatch(
          commentCount: nextCount,
        );
        ref.read(communityFeedControllerProvider(widget.community.id).notifier).applyPublication(
              item.id,
              patch,
            );
        syncCommunityPublication(
          ref,
          publicationId: item.id,
          communityId: widget.community.id,
          patch: patch,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final community = widget.community;
    final state = ref.watch(communityFeedControllerProvider(community.id));
    return ListView(
      key: const ValueKey('community-feed-scroll'),
      controller: _scrollController,
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
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.author.displayLabel,
                                    style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                                  ),
                                ),
                                if (_canModeratorDelete(item))
                                  PopupMenuButton<String>(
                                    key: ValueKey('community-feed-mod-menu-${item.id}'),
                                    tooltip: 'Actions',
                                    icon: Icon(Icons.more_vert, color: colors.textSecondary),
                                    onSelected: (value) {
                                      if (value == 'delete') {
                                        _confirmModeratorDelete(item);
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            ChroniqueCard(
                              key: ValueKey('community-feed-item-${item.id}'),
                              chronique: item.asChronique(),
                              showFeedMedia: true,
                              menuEnabled: false,
                              onTap: _isAuthor(item) ? () => _openAuthorDetail(item) : null,
                              onMediaSelected: (media) => _openMedia(context, media),
                            ),
                            CommunityPublicationSocialBar(
                              publication: item,
                              showFavorite: !_isAuthor(item),
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
                              onFavorite: () async {
                                final ok = await ref
                                    .read(communityFeedControllerProvider(community.id).notifier)
                                    .toggleFavorite(item);
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Impossible de mettre à jour le favori')),
                                  );
                                }
                              },
                              onComments: () => _openComments(item),
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
