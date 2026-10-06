import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../chronique/models/chronique_date.dart';
import '../state/community_comment_traces_controller.dart';

class CommunityCommentTracesScreen extends ConsumerWidget {
  const CommunityCommentTracesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final state = ref.watch(communityCommentTracesControllerProvider);
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(title: const Text('Mes traces de commentaires')),
      body: switch (state) {
        CommunityCommentTracesLoading() => const AppLoading(),
        CommunityCommentTracesError(:final message) => Center(
            child: Text(message, key: const ValueKey('community-comment-traces-error')),
          ),
        CommunityCommentTracesReady(:final items) => items.isEmpty
            ? Center(
                child: Text(
                  'Aucune trace',
                  key: const ValueKey('community-comment-traces-empty'),
                  style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.isEphemeral ? 'Publication éphémère expirée' : 'Trace de commentaire',
                              style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                            ),
                            if (item.publicationAuthorLogin != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Publication de ${item.publicationAuthorLogin}',
                                style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              item.commentBody,
                              key: ValueKey('community-comment-trace-${item.id}'),
                              style: AppTextTheme.bodyMedium,
                            ),
                            if (_format(item.commentCreatedAt) != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Commentaire du ${_format(item.commentCreatedAt)}',
                                key: ValueKey('community-comment-trace-at-${item.id}'),
                                style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                              ),
                            ],
                            if (_format(item.publishedAt) != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Publiée le ${_format(item.publishedAt)}',
                                style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                              ),
                            ],
                            if (_format(item.expiredAt) != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Expirée le ${_format(item.expiredAt)}',
                                style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      },
    );
  }

  String? _format(String? raw) {
    if (raw == null) {
      return null;
    }
    return formatOptionalChroniqueDate(DateTime.tryParse(raw));
  }
}
