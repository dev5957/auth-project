import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/community_publication.dart';

class CommunityPublicationSocialBar extends StatelessWidget {
  const CommunityPublicationSocialBar({
    super.key,
    required this.publication,
    this.onLike,
    this.onComments,
    this.onFavorite,
    this.likeEnabled = true,
    this.favoriteEnabled = true,
    this.showFavorite = true,
  });

  final CommunityPublication publication;
  final VoidCallback? onLike;
  final VoidCallback? onComments;
  final VoidCallback? onFavorite;
  final bool likeEnabled;
  final bool favoriteEnabled;
  final bool showFavorite;

  static const double commentsDisabledOpacity = 0.38;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final commentsEnabled = publication.commentsEnabled;
    final commentsColor = commentsEnabled
        ? colors.textSecondary
        : colors.textSecondary.withValues(alpha: commentsDisabledOpacity);
    return Row(
      children: [
        IconButton(
          key: ValueKey('community-like-${publication.id}'),
          tooltip: publication.likedByMe ? 'Retirer le j’aime' : 'J’aime',
          onPressed: likeEnabled ? onLike : null,
          icon: Icon(
            publication.likedByMe ? Icons.favorite : Icons.favorite_border,
            color: publication.likedByMe ? colors.danger : colors.textSecondary,
          ),
        ),
        Text(
          '${publication.likeCount}',
          key: ValueKey('community-like-count-${publication.id}'),
          style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
        ),
        IconButton(
          key: ValueKey('community-comments-${publication.id}'),
          tooltip: commentsEnabled ? 'Commentaires' : 'Commentaires désactivés',
          onPressed: commentsEnabled ? onComments : null,
          icon: Icon(
            Icons.chat_bubble_outline,
            color: commentsColor,
          ),
        ),
        Text(
          '${publication.commentCount}',
          key: ValueKey('community-comment-count-${publication.id}'),
          style: AppTextTheme.labelSmall.copyWith(color: commentsColor),
        ),
        if (showFavorite)
          IconButton(
            key: ValueKey('community-favorite-${publication.id}'),
            tooltip: publication.favoritedByMe ? 'Retirer des favoris' : 'Ajouter aux favoris',
            onPressed: favoriteEnabled ? onFavorite : null,
            icon: Icon(
              publication.favoritedByMe ? Icons.bookmark : Icons.bookmark_border,
              color: publication.favoritedByMe ? colors.primary : colors.textSecondary,
            ),
          )
        else
          IconButton(
            key: ValueKey('community-favorite-count-icon-${publication.id}'),
            tooltip: 'Favoris reçus',
            onPressed: null,
            style: IconButton.styleFrom(
              foregroundColor: colors.textSecondary,
              disabledForegroundColor: colors.textSecondary,
            ),
            icon: Icon(
              Icons.bookmark_border,
              color: colors.textSecondary,
            ),
          ),
        Text(
          '${publication.favoriteCount}',
          key: ValueKey('community-favorite-count-${publication.id}'),
          style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}
