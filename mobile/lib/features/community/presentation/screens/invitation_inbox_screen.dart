import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../models/community.dart';
import '../../models/invitation_messages.dart';
import '../state/invitation_inbox_controller.dart';

class InvitationInboxScreen extends ConsumerWidget {
  const InvitationInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final state = ref.watch(invitationInboxControllerProvider);

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text('Invitations'),
      ),
      body: SafeArea(
        child: switch (state) {
          InvitationInboxLoading() => const AppLoading(),
          InvitationInboxError(:final message, :final statusCode) => Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    statusCode == 401 ? 'Session expirée' : message,
                    key: const ValueKey('invitation-inbox-error'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    key: const ValueKey('invitation-inbox-retry'),
                    label: 'Réessayer',
                    onPressed: () =>
                        ref.read(invitationInboxControllerProvider.notifier).load(),
                  ),
                ],
              ),
            ),
          InvitationInboxReady(:final items, :final mutatingId, :final notice, :final actionError) =>
            items.isEmpty && notice == null && actionError == null
                ? const Center(
                    child: Text(
                      InvitationMessages.emptyInbox,
                      key: ValueKey('invitation-inbox-empty'),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      if (notice != null) ...[
                        Text(
                          notice,
                          key: const ValueKey('invitation-inbox-notice'),
                          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (actionError != null) ...[
                        Text(
                          actionError,
                          key: const ValueKey('invitation-inbox-action-error'),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (items.isEmpty)
                        const Text(
                          InvitationMessages.emptyInbox,
                          key: ValueKey('invitation-inbox-empty'),
                        )
                      else
                        for (final item in items) ...[
                          _InvitationCard(
                            invitation: item,
                            mutating: mutatingId == item.id,
                            actionsEnabled: mutatingId == null,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                    ],
                  ),
        },
      ),
    );
  }
}

class _InvitationCard extends ConsumerWidget {
  const _InvitationCard({
    required this.invitation,
    required this.mutating,
    required this.actionsEnabled,
  });

  final ReceivedCommunityInvitation invitation;
  final bool mutating;
  final bool actionsEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final busy = mutating || !actionsEnabled;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            invitation.communityName,
            key: ValueKey('invitation-inbox-item-${invitation.id}'),
            style: AppTextTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Invité par ${invitation.invitedByLogin}',
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
          if (invitation.receivedOnLabel.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              invitation.receivedOnLabel,
              style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: ValueKey('invitation-inbox-accept-${invitation.id}'),
            label: 'Accepter',
            isLoading: mutating,
            onPressed: busy
                ? null
                : () => ref.read(invitationInboxControllerProvider.notifier).accept(invitation.id),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: ValueKey('invitation-inbox-decline-${invitation.id}'),
            label: 'Refuser',
            variant: AppButtonVariant.secondary,
            onPressed: busy
                ? null
                : () => ref.read(invitationInboxControllerProvider.notifier).decline(invitation.id),
          ),
        ],
      ),
    );
  }
}
