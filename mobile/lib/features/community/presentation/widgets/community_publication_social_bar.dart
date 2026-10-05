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
    this.likeEnabled = true,
  });

  final CommunityPublication publication;
  final VoidCallback? onLike;
  final VoidCallback? onComments;
  final bool likeEnabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
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
          tooltip: 'Commentaires',
          onPressed: onComments,
          icon: Icon(Icons.chat_bubble_outline, color: colors.textSecondary),
        ),
        Text(
          '${publication.commentCount}',
          key: ValueKey('community-comment-count-${publication.id}'),
          style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}
