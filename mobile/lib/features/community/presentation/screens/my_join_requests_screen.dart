import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../models/join_request.dart';
import '../../models/join_request_messages.dart';
import '../state/my_join_requests_controller.dart';

class MyJoinRequestsScreen extends ConsumerWidget {
  const MyJoinRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final state = ref.watch(myJoinRequestsControllerProvider);

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text(JoinRequestMessages.mineTitle),
      ),
      body: SafeArea(
        child: switch (state) {
          MyJoinRequestsLoading() => const AppLoading(),
          MyJoinRequestsError(:final message, :final statusCode) => Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    statusCode == 401 ? 'Session expirée' : message,
                    key: const ValueKey('my-join-requests-error'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    key: const ValueKey('my-join-requests-retry'),
                    label: 'Réessayer',
                    onPressed: () =>
                        ref.read(myJoinRequestsControllerProvider.notifier).load(),
                  ),
                ],
              ),
            ),
          MyJoinRequestsReady(:final items, :final notice) => items.isEmpty && notice == null
              ? const Center(
                  child: Text(
                    JoinRequestMessages.mineEmpty,
                    key: ValueKey('my-join-requests-empty'),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (notice != null) ...[
                      Text(
                        notice,
                        key: const ValueKey('my-join-requests-notice'),
                        style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    if (items.isEmpty)
                      const Text(
                        JoinRequestMessages.mineEmpty,
                        key: ValueKey('my-join-requests-empty'),
                      )
                    else
                      for (final item in items) ...[
                        _MineJoinRequestCard(request: item),
                        const SizedBox(height: AppSpacing.md),
                      ],
                  ],
                ),
        },
      ),
    );
  }
}

class _MineJoinRequestCard extends StatelessWidget {
  const _MineJoinRequestCard({required this.request});

  final MyJoinRequest request;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.communityName,
            key: ValueKey('my-join-request-item-${request.id}'),
            style: AppTextTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            JoinRequestMessages.mineStatusLabel(request.status),
            key: ValueKey('my-join-request-status-${request.id}'),
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
          if (request.requestedOnLabel.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              request.requestedOnLabel,
              key: ValueKey('my-join-request-date-${request.id}'),
              style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
