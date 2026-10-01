import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_loading.dart';
import '../state/community_list_controller.dart';
import '../widgets/community_media_placeholder.dart';

class CommunityListScreen extends ConsumerWidget {
  const CommunityListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final state = ref.watch(communityListControllerProvider);

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text('Mes communautés'),
      ),
      body: SafeArea(
        child: switch (state) {
          CommunityListLoading() => const AppLoading(),
          CommunityListError(:final message, :final statusCode) => Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    statusCode == 401 ? 'Session expirée' : message,
                    key: const ValueKey('community-list-error'),
                    style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'Réessayer',
                    onPressed: () => ref.read(communityListControllerProvider.notifier).load(),
                  ),
                ],
              ),
            ),
          CommunityListReady(:final items) => items.isEmpty
              ? const Center(
                  child: Text('Aucune communauté pour le moment'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final community = items[index];
                    return AppCard(
                      child: InkWell(
                        key: ValueKey('community-list-item-${community.id}'),
                        onTap: () => context.push(AppRoutes.communityDetail(community.id)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const CommunityMediaPlaceholder(label: 'Avatar', height: 56),
                            const SizedBox(height: AppSpacing.md),
                            Text(community.name, style: AppTextTheme.titleMedium),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              community.myRole.label,
                              style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: AppButton(
            key: const ValueKey('community-create-open'),
            label: 'Créer une communauté',
            onPressed: () => context.push(AppRoutes.communitiesCreate),
          ),
        ),
      ),
    );
  }
}
