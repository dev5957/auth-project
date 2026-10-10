import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../auth/providers/auth_controller.dart';
import '../../../auth/state/auth_state.dart';
import '../../../chronique/models/chronique.dart';
import '../../../chronique/presentation/widgets/chronique_card.dart';
import '../../../chronique/presentation/widgets/chronique_media_viewer.dart';
import '../../models/community.dart';
import '../../models/community_publication.dart';
import '../state/my_favorites_controller.dart';
import '../widgets/community_comments_sheet.dart';
import '../widgets/community_publication_social_bar.dart';

class MyFavoritesScreen extends ConsumerWidget {
  const MyFavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final state = ref.watch(myFavoritesControllerProvider);
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(title: const Text('Mes favoris')),
      body: switch (state) {
        MyFavoritesLoading() => const AppLoading(),
        MyFavoritesError(:final message) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message, key: const ValueKey('my-favorites-error')),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    key: const ValueKey('my-favorites-retry'),
                    label: 'Réessayer',
                    onPressed: () => ref.read(myFavoritesControllerProvider.notifier).load(),
                  ),
                ],
              ),
            ),
          ),
        MyFavoritesReady(:final items, :final next, :final loadingMore) => items.isEmpty
            ? Center(
                child: Text(
                  'Aucun favori pour le moment',
                  key: const ValueKey('my-favorites-empty'),
                  style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                ),
              )
            : RefreshIndicator(
                onRefresh: () => ref.read(myFavoritesControllerProvider.notifier).load(),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  children: [
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _FavoriteCard(publication: item),
                      ),
                    if (next != null)
                      AppButton(
                        key: const ValueKey('my-favorites-load-more'),
                        label: loadingMore ? 'Chargement…' : 'Charger plus',
                        onPressed: loadingMore
                            ? null
                            : () => ref.read(myFavoritesControllerProvider.notifier).loadMore(),
                      ),
                  ],
                ),
              ),
      },
    );
  }
}

class _FavoriteCard extends ConsumerWidget {
  const _FavoriteCard({required this.publication});

  final CommunityPublication publication;

  int? _viewerId(WidgetRef ref) {
    final auth = ref.read(authControllerProvider);
    if (auth is AuthAuthenticated) {
      return auth.user.id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final viewerId = _viewerId(ref);
    final isAuthor = viewerId != null && publication.author.userId == viewerId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          publication.author.displayLabel,
          style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
        ),
        if (publication.communityName != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            publication.communityName!,
            style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        ChroniqueCard(
          key: ValueKey('my-favorite-item-${publication.id}'),
          chronique: publication.asChronique(),
          showFeedMedia: true,
          menuEnabled: false,
          onTap: null,
          onMediaSelected: (media) => _openMedia(context, media),
        ),
        CommunityPublicationSocialBar(
          publication: publication,
          showFavorite: !isAuthor,
          onLike: () async {
            final ok = await ref.read(myFavoritesControllerProvider.notifier).toggleLike(publication);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Impossible de mettre à jour le j’aime')),
              );
            }
          },
          onFavorite: () async {
            final ok = await ref.read(myFavoritesControllerProvider.notifier).toggleFavorite(publication);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Impossible de mettre à jour le favori')),
              );
            }
          },
          onComments: () => _openComments(context, ref, publication, isAuthor),
        ),
      ],
    );
  }

  void _openMedia(BuildContext context, ChroniqueMedia media) {
    FocusManager.instance.primaryFocus?.unfocus();
    openChroniqueFeedMedia(context, media);
  }

  Future<void> _openComments(
    BuildContext context,
    WidgetRef ref,
    CommunityPublication item,
    bool isAuthor,
  ) {
    FocusManager.instance.primaryFocus?.unfocus();
    return showCommunityCommentsSheet(
      context: context,
      community: Community(
        id: item.communityId,
        name: item.communityName ?? 'Communauté',
        visibility: 'private',
        myRole: CommunityRole.member,
        memberCount: 0,
      ),
      publication: item,
      isPublicationAuthor: isAuthor,
    );
  }
}
