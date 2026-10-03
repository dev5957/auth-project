import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../models/community.dart';
import '../state/community_detail_controller.dart';
import '../state/community_list_controller.dart';
import '../widgets/community_join_requests_section.dart';
import '../widgets/community_leave_bar.dart';
import '../widgets/community_media_placeholder.dart';
import '../widgets/community_member_dialogs.dart';
import '../widgets/community_member_tile.dart';
import '../widgets/community_owner_leave_flow.dart';
import '../widgets/sent_invitations_section.dart';

class CommunityDetailScreen extends ConsumerWidget {
  const CommunityDetailScreen({super.key, required this.communityId});

  final int communityId;

  Future<void> _onPromote(
    BuildContext context,
    WidgetRef ref,
    CommunityMember member,
  ) async {
    final confirmed = await confirmPromoteMember(context, login: member.login);
    if (!confirmed) {
      return;
    }
    final ok = await ref
        .read(communityDetailControllerProvider(communityId).notifier)
        .updateMemberRole(userId: member.userId, role: 'admin');
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de modifier ce rôle')),
      );
    }
  }

  Future<void> _onDemote(
    BuildContext context,
    WidgetRef ref,
    CommunityMember member,
  ) async {
    final confirmed = await confirmDemoteAdmin(context, login: member.login);
    if (!confirmed) {
      return;
    }
    final ok = await ref
        .read(communityDetailControllerProvider(communityId).notifier)
        .updateMemberRole(userId: member.userId, role: 'member');
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de modifier ce rôle')),
      );
    }
  }

  Future<void> _onRemove(
    BuildContext context,
    WidgetRef ref,
    CommunityMember member,
  ) async {
    final confirmed = await confirmRemoveMember(context, login: member.login);
    if (!confirmed) {
      return;
    }
    final ok = await ref
        .read(communityDetailControllerProvider(communityId).notifier)
        .removeMember(member.userId);
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de retirer ce membre')),
      );
    }
  }

  Future<void> _onLeave(
    BuildContext context,
    WidgetRef ref,
    Community community,
    List<CommunityMember> members,
  ) async {
    final notifier = ref.read(communityDetailControllerProvider(communityId).notifier);
    final left = await runCommunityLeaveFlow(
      context: context,
      myRole: community.myRole,
      members: members,
      updateMemberRole: notifier.updateMemberRole,
      leave: notifier.leave,
      onError: (message) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        }
      },
    );
    if (!left || !context.mounted) {
      return;
    }
    await ref.read(communityListControllerProvider.notifier).load();
    if (!context.mounted) {
      return;
    }
    context.pop();
  }

  Future<void> _returnToCommunityList(BuildContext context, WidgetRef ref) async {
    await ref.read(communityListControllerProvider.notifier).load();
    if (!context.mounted) {
      return;
    }
    context.go(AppRoutes.communities);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final state = ref.watch(communityDetailControllerProvider(communityId));

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text('Communauté'),
        leading: IconButton(
          key: const ValueKey('community-detail-close'),
          tooltip: 'Retour',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _returnToCommunityList(context, ref),
        ),
      ),
      body: SafeArea(
        child: switch (state) {
          CommunityDetailLoading() => const AppLoading(),
          CommunityDetailError(:final message, :final statusCode) => Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    statusCode == 404
                        ? 'Communauté introuvable'
                        : statusCode == 401
                            ? 'Session expirée'
                            : message,
                    key: const ValueKey('community-detail-error'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    key: const ValueKey('community-detail-error-back'),
                    label: 'Retour aux communautés',
                    onPressed: () => _returnToCommunityList(context, ref),
                  ),
                ],
              ),
            ),
          CommunityDetailReady(:final data) => ListView(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              children: [
                const CommunityMediaPlaceholder(label: 'Bannière', height: 120),
                const SizedBox(height: AppSpacing.lg),
                const CommunityMediaPlaceholder(label: 'Avatar', height: 72),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  data.community.name,
                  key: const ValueKey('community-detail-name'),
                  style: AppTextTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  data.community.myRole.label,
                  key: const ValueKey('community-detail-role'),
                  style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                ),
                if (data.community.myRole == CommunityRole.owner ||
                    data.community.myRole == CommunityRole.admin) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    key: const ValueKey('community-detail-invite'),
                    label: 'Inviter un membre',
                    onPressed: () =>
                        context.push(AppRoutes.communityInviteSearch(data.community.id)),
                  ),
                  SentInvitationsSection(communityId: data.community.id),
                ],
                if (data.community.myRole == CommunityRole.owner)
                  CommunityJoinRequestsSection(communityId: data.community.id),
                if (data.community.description != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(data.community.description!),
                ],
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Membres (${data.community.memberCount})',
                  style: AppTextTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                for (final member in data.members)
                  CommunityMemberTile(
                    member: member,
                    viewerRole: data.community.myRole,
                    onPromote: () => _onPromote(context, ref, member),
                    onDemote: () => _onDemote(context, ref, member),
                    onRemove: () => _onRemove(context, ref, member),
                  ),
                CommunityLeaveBar(
                  myRole: data.community.myRole,
                  onLeave: () => _onLeave(
                    context,
                    ref,
                    data.community,
                    data.members,
                  ),
                ),
              ],
            ),
        },
      ),
    );
  }
}
