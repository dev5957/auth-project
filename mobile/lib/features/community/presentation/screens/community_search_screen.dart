import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../models/community.dart';
import '../../models/join_request_messages.dart';
import '../state/community_search_controller.dart';

class CommunitySearchScreen extends ConsumerStatefulWidget {
  const CommunitySearchScreen({super.key});

  @override
  ConsumerState<CommunitySearchScreen> createState() => _CommunitySearchScreenState();
}

class _CommunitySearchScreenState extends ConsumerState<CommunitySearchScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _submit() {
    ref.read(communitySearchControllerProvider.notifier).submit(_query.text);
  }

  Future<void> _openPreview(CommunitySearchPreview preview) async {
    final opened = await ref
        .read(communitySearchControllerProvider.notifier)
        .openAccessibleDetail(preview.id);
    if (!opened || !mounted) {
      return;
    }
    context.push(AppRoutes.communityDetail(preview.id));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final state = ref.watch(communitySearchControllerProvider);
    final idle = state is CommunitySearchIdle ? state : null;
    final loading = state is CommunitySearchLoading;

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text('Rechercher une communauté'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    key: const ValueKey('community-search-field'),
                    label: 'Nom de la communauté',
                    controller: _query,
                    errorText: idle?.queryError,
                    textInputAction: TextInputAction.search,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    key: const ValueKey('community-search-submit'),
                    label: 'Rechercher',
                    isLoading: loading,
                    onPressed: loading ? null : _submit,
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (state) {
                CommunitySearchIdle() => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                    child: Text(
                      'Recherchez une communauté par son nom.',
                      key: ValueKey('community-search-idle'),
                    ),
                  ),
                CommunitySearchLoading() => const AppLoading(),
                CommunitySearchEmpty() => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                    child: Text(
                      'Aucune communauté trouvée',
                      key: ValueKey('community-search-empty'),
                    ),
                  ),
                CommunitySearchError(:final message, :final statusCode) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                    child: Text(
                      statusCode == 401 ? 'Session expirée' : message,
                      key: const ValueKey('community-search-error'),
                    ),
                  ),
                CommunitySearchReady(
                  :final items,
                  :final notice,
                  :final mutatingCommunityId,
                  :final actionError,
                  :final memberCommunityIds,
                  :final pendingCommunityIds,
                ) =>
                  ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    children: [
                      if (notice != null && notice.isNotEmpty) ...[
                        Text(
                          notice,
                          key: const ValueKey('community-search-private'),
                          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (actionError != null) ...[
                        Text(
                          actionError,
                          key: const ValueKey('community-search-join-error'),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      for (final preview in items) ...[
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              InkWell(
                                key: ValueKey('community-search-item-${preview.id}'),
                                onTap: () => _openPreview(preview),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(preview.name, style: AppTextTheme.titleMedium),
                                    if (preview.description != null) ...[
                                      const SizedBox(height: AppSpacing.sm),
                                      Text(preview.description!),
                                    ],
                                    const SizedBox(height: AppSpacing.sm),
                                    Text(
                                      '${preview.memberCount} membre${preview.memberCount == 1 ? '' : 's'}',
                                      key: ValueKey('community-search-count-${preview.id}'),
                                      style: AppTextTheme.bodyMedium.copyWith(
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!memberCommunityIds.contains(preview.id) &&
                                  !pendingCommunityIds.contains(preview.id)) ...[
                                const SizedBox(height: AppSpacing.md),
                                AppButton(
                                  key: ValueKey('community-search-join-${preview.id}'),
                                  label: JoinRequestMessages.askToJoin,
                                  isLoading: mutatingCommunityId == preview.id,
                                  onPressed: mutatingCommunityId != null
                                      ? null
                                      : () => ref
                                          .read(communitySearchControllerProvider.notifier)
                                          .requestJoin(preview.id),
                                ),
                              ] else if (pendingCommunityIds.contains(preview.id)) ...[
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  JoinRequestMessages.pending,
                                  key: ValueKey('community-search-pending-${preview.id}'),
                                  style: AppTextTheme.bodyMedium.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}
