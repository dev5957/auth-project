import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';

/// Hub V1 : CREATE et EXPLORE côte à côte, sans appels métier.
class HomeCreateExploreActions extends StatelessWidget {
  const HomeCreateExploreActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
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
    );
  }
}
