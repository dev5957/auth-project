import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../models/community.dart';

class CommunityLeaveBar extends StatelessWidget {
  const CommunityLeaveBar({
    super.key,
    required this.myRole,
    required this.onLeave,
  });

  final CommunityRole myRole;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final label = myRole == CommunityRole.owner
        ? 'Quitter et transférer'
        : 'Quitter la communauté';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: AppButton(
        key: const ValueKey('community-leave'),
        label: label,
        variant: AppButtonVariant.secondary,
        onPressed: onLeave,
      ),
    );
  }
}
