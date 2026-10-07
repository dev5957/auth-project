import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../models/community.dart';
import '../../models/community_publication.dart';
import 'community_comments_section.dart';

Future<void> showCommunityCommentsSheet({
  required BuildContext context,
  required Community community,
  required CommunityPublication publication,
  required bool isPublicationAuthor,
  ValueChanged<int>? onCountDelta,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.luminaColors.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.lg)),
    ),
    builder: (sheetContext) {
      final height = MediaQuery.sizeOf(sheetContext).height * 0.62;
      final keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(
          key: ValueKey('community-comments-sheet-${publication.id}'),
          height: height,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.md),
            child: CommunityCommentsSection(
              communityId: community.id,
              publicationId: publication.id,
              commentsEnabled: publication.commentsEnabled,
              isPublicationAuthor: isPublicationAuthor,
              myRole: community.myRole,
              keyPrefix: 'community-feed-${publication.id}',
              composerAtBottom: true,
              onCountDelta: onCountDelta,
            ),
          ),
        ),
      );
    },
  );
}
