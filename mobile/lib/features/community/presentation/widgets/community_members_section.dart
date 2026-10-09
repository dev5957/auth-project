import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../models/community.dart';
import 'community_leave_bar.dart';
import 'community_member_tile.dart';

class CommunityMembersSection extends StatelessWidget {
  const CommunityMembersSection({
    super.key,
    required this.community,
    required this.members,
    required this.onPromote,
    required this.onDemote,
    required this.onRemove,
    required this.onLeave,
  });

  final Community community;
  final List<CommunityMember> members;
  final ValueChanged<CommunityMember> onPromote;
  final ValueChanged<CommunityMember> onDemote;
  final ValueChanged<CommunityMember> onRemove;
  final VoidCallback onLeave;

  bool get _canInvite =>
      community.myRole == CommunityRole.owner || community.myRole == CommunityRole.admin;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('community-members-scroll'),
      padding: const EdgeInsets.all(AppSpacing.xxl),
      children: [
        Text(
          'Membres (${community.memberCount})',
          style: AppTextTheme.titleMedium,
        ),
        if (_canInvite) ...[
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('community-detail-invite'),
            label: 'Inviter un membre',
            onPressed: () => context.push(AppRoutes.communityInviteSearch(community.id)),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        for (final member in members)
          CommunityMemberTile(
            member: member,
            viewerRole: community.myRole,
            onPromote: () => onPromote(member),
            onDemote: () => onDemote(member),
            onRemove: () => onRemove(member),
          ),
        CommunityLeaveBar(
          myRole: community.myRole,
          onLeave: onLeave,
        ),
      ],
    );
  }
}
