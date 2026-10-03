import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/community.dart';

class CommunityMemberTile extends StatelessWidget {
  const CommunityMemberTile({
    super.key,
    required this.member,
    required this.viewerRole,
    this.onPromote,
    this.onDemote,
    this.onRemove,
  });

  final CommunityMember member;
  final CommunityRole viewerRole;
  final VoidCallback? onPromote;
  final VoidCallback? onDemote;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final ownerControls =
        viewerRole == CommunityRole.owner && member.role != CommunityRole.owner;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${member.login} · ${member.role.label}',
            key: ValueKey('community-member-${member.userId}'),
          ),
          if (ownerControls) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                if (member.role == CommunityRole.member)
                  TextButton(
                    key: ValueKey('community-promote-${member.userId}'),
                    onPressed: onPromote,
                    child: const Text('Nommer admin'),
                  ),
                if (member.role == CommunityRole.admin)
                  TextButton(
                    key: ValueKey('community-demote-${member.userId}'),
                    onPressed: onDemote,
                    child: const Text('Rétrograder'),
                  ),
                TextButton(
                  key: ValueKey('community-remove-${member.userId}'),
                  onPressed: onRemove,
                  child: Text(
                    'Retirer',
                    style: AppTextTheme.bodyMedium.copyWith(color: colors.danger),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
