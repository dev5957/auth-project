import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../models/join_request.dart';
import '../../models/join_request_messages.dart';
import '../state/community_join_requests_controller.dart';
import 'community_management_section_card.dart';

class CommunityJoinRequestsSection extends ConsumerWidget {
  const CommunityJoinRequestsSection({super.key, required this.communityId});

  final int communityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final state = ref.watch(communityJoinRequestsControllerProvider(communityId));

    final pendingBody = switch (state) {
      CommunityJoinRequestsLoading() => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: AppLoading(),
        ),
      CommunityJoinRequestsError(:final message, :final statusCode) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              statusCode == 401 ? 'Session expirée' : message,
              key: const ValueKey('community-join-requests-error'),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              key: const ValueKey('community-join-requests-retry'),
              label: 'Réessayer',
              onPressed: () => ref
                  .read(communityJoinRequestsControllerProvider(communityId).notifier)
                  .load(),
            ),
          ],
        ),
      CommunityJoinRequestsReady(
        :final pending,
        :final mutatingId,
        :final notice,
        :final actionError,
      ) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notice != null) ...[
              Text(
                notice,
                key: const ValueKey('community-join-requests-notice'),
                style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (actionError != null) ...[
              Text(
                actionError,
                key: const ValueKey('community-join-requests-action-error'),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (pending.isEmpty)
              const Text(
                JoinRequestMessages.ownerPendingEmpty,
                key: ValueKey('community-join-requests-pending-empty'),
              )
            else
              for (final item in pending) ...[
                _OwnerPendingCard(
                  request: item,
                  mutating: mutatingId == item.id,
                  actionsEnabled: mutatingId == null,
                  communityId: communityId,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
          ],
        ),
    };

    final historyBody = switch (state) {
      CommunityJoinRequestsLoading() => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: AppLoading(),
        ),
      CommunityJoinRequestsError() => const SizedBox.shrink(),
      CommunityJoinRequestsReady(:final history) => history.isEmpty
          ? const Text(
              JoinRequestMessages.ownerHistoryEmpty,
              key: ValueKey('community-join-requests-history-empty'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in history) ...[
                  _OwnerHistoryCard(request: item),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommunityManagementSectionCard(
          key: const ValueKey('community-manage-join-requests'),
          title: JoinRequestMessages.ownerTitle,
          titleKey: const ValueKey('community-join-requests-title'),
          child: pendingBody,
        ),
        CommunityManagementSectionCard(
          key: const ValueKey('community-manage-history'),
          title: JoinRequestMessages.ownerHistoryTitle,
          titleKey: const ValueKey('community-join-requests-history-title'),
          child: historyBody,
        ),
      ],
    );
  }
}

class _OwnerPendingCard extends ConsumerWidget {
  const _OwnerPendingCard({
    required this.request,
    required this.mutating,
    required this.actionsEnabled,
    required this.communityId,
  });

  final OwnerJoinRequest request;
  final bool mutating;
  final bool actionsEnabled;
  final int communityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final busy = mutating || !actionsEnabled;
    final login = request.requesterLogin;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (login != null)
            Text(
              login,
              key: ValueKey('community-join-request-login-${request.id}'),
              style: AppTextTheme.titleMedium,
            ),
          if (login != null) const SizedBox(height: AppSpacing.sm),
          Text(
            JoinRequestMessages.ownerStatusLabel(request.status),
            key: ValueKey('community-join-request-pending-${request.id}'),
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
          if (request.requestedOnLabel.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              request.requestedOnLabel,
              style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: ValueKey('community-join-accept-${request.id}'),
            label: JoinRequestMessages.accept,
            isLoading: mutating,
            onPressed: busy
                ? null
                : () => ref
                    .read(communityJoinRequestsControllerProvider(communityId).notifier)
                    .accept(request.id),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: ValueKey('community-join-decline-${request.id}'),
            label: JoinRequestMessages.decline,
            variant: AppButtonVariant.secondary,
            onPressed: busy
                ? null
                : () => ref
                    .read(communityJoinRequestsControllerProvider(communityId).notifier)
                    .decline(request.id),
          ),
        ],
      ),
    );
  }
}

class _OwnerHistoryCard extends StatelessWidget {
  const _OwnerHistoryCard({required this.request});

  final OwnerJoinRequest request;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final login = request.requesterLogin;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (login != null)
            Text(
              login,
              key: ValueKey('community-join-history-login-${request.id}'),
              style: AppTextTheme.titleMedium,
            ),
          if (login != null) const SizedBox(height: AppSpacing.sm),
          Text(
            JoinRequestMessages.ownerStatusLabel(request.status),
            key: ValueKey('community-join-history-${request.id}'),
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
