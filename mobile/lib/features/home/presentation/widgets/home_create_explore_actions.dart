import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';

/// Hub V1 : CREATE, EXPLORE et communautés.
class HomeCreateExploreActions extends StatelessWidget {
  const HomeCreateExploreActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'CREATE',
                onPressed: () => context.push(AppRoutes.create),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppButton(
                label: 'EXPLORE',
                variant: AppButtonVariant.secondary,
                onPressed: () => context.push(AppRoutes.explore),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('home-communities'),
          label: 'COMMUNITIES',
          variant: AppButtonVariant.secondary,
          onPressed: () => context.push(AppRoutes.communities),
        ),
      ],
    );
  }
}
