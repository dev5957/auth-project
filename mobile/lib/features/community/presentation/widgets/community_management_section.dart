import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/community.dart';
import 'community_join_requests_section.dart';
import 'sent_invitations_section.dart';

class CommunityManagementSection extends StatelessWidget {
  const CommunityManagementSection({
    super.key,
    required this.community,
  });

  final Community community;

  bool get _canSeeInvitations =>
      community.myRole == CommunityRole.owner || community.myRole == CommunityRole.admin;

  bool get _canSeeJoinRequests => community.myRole == CommunityRole.owner;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('community-manage-scroll'),
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.md, AppSpacing.xxl, AppSpacing.xxl),
      children: [
        const Text('Gestion', style: AppTextTheme.titleMedium),
        if (_canSeeInvitations) SentInvitationsSection(communityId: community.id),
        if (_canSeeJoinRequests) CommunityJoinRequestsSection(communityId: community.id),
      ],
    );
  }
}
