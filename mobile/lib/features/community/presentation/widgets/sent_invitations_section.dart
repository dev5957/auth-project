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
import '../state/sent_invitations_controller.dart';
import 'community_management_section_card.dart';

class SentInvitationsSection extends ConsumerWidget {
  const SentInvitationsSection({super.key, required this.communityId});

  final int communityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sentInvitationsControllerProvider(communityId));

    return CommunityManagementSectionCard(
      key: const ValueKey('community-manage-invitations'),
      title: InvitationMessages.sentSectionTitle,
      titleKey: const ValueKey('community-sent-invitations-title'),
      child: switch (state) {
        SentInvitationsLoading() => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: AppLoading(),
          ),
        SentInvitationsError(:final message, :final statusCode) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                statusCode == 401 ? 'Session expirée' : message,
                key: const ValueKey('community-sent-invitations-error'),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                key: const ValueKey('community-sent-invitations-retry'),
                label: 'Réessayer',
                onPressed: () =>
                    ref.read(sentInvitationsControllerProvider(communityId).notifier).load(),
              ),
            ],
          ),
        SentInvitationsReady(:final items) => items.isEmpty
            ? const Text(
                InvitationMessages.sentEmpty,
                key: ValueKey('community-sent-invitations-empty'),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in items) ...[
                    _SentInvitationCard(invitation: item),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ],
              ),
      },
    );
  }
}

class _SentInvitationCard extends StatelessWidget {
  const _SentInvitationCard({required this.invitation});

  final SentCommunityInvitation invitation;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final login = invitation.inviteeLogin;
    final declinedOn = invitation.declinedOnLabel;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (login != null)
            Text(
              login,
              key: ValueKey('community-sent-invitation-login-${invitation.id}'),
              style: AppTextTheme.titleMedium,
            ),
          if (login != null) const SizedBox(height: AppSpacing.sm),
          Text(
            InvitationMessages.sentStatusLabel(invitation.status),
            key: ValueKey('community-sent-invitation-status-${invitation.id}'),
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
          if (declinedOn.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Refusée le $declinedOn',
              key: ValueKey('community-sent-invitation-declined-at-${invitation.id}'),
              style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
