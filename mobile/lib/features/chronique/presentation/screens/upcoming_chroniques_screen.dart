import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../models/chronique.dart';
import '../../models/chronique_fields.dart';
import '../../providers/chronique_providers.dart';
import '../state/upcoming_chroniques_controller.dart';
import '../widgets/chronique_card.dart';
import '../widgets/chronique_card_menu.dart';
import '../widgets/chronique_lifecycle_dialogs.dart';

/// Publications programmées : `GET /chroniques?status=scheduled`.
class UpcomingChroniquesScreen extends ConsumerWidget {
  const UpcomingChroniquesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final state = ref.watch(upcomingChroniquesControllerProvider);

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        title: Text(
          'À venir',
          style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
        ),
      ),
      body: SafeArea(child: _body(context, ref, state)),
    );
  }

  Future<void> _onRefresh(WidgetRef ref) {
    return ref.read(upcomingChroniquesControllerProvider.notifier).refresh();
  }

  Widget _refreshable({
    required WidgetRef ref,
    required Widget child,
  }) {
    return RefreshIndicator(
      onRefresh: () => _onRefresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 360,
            child: child,
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    Chronique chronique,
    ChroniqueCardMenuAction action,
  ) async {
    switch (action) {
      case ChroniqueCardMenuAction.edit:
        final updated = await context.push<Chronique>(
          AppRoutes.chroniqueEdit(chronique.id),
          extra: chronique,
        );
        if (updated != null) {
          ref.read(upcomingChroniquesControllerProvider.notifier).upsert(updated);
        }
      case ChroniqueCardMenuAction.delete:
        final confirmed = await confirmDeleteChronique(context, scheduled: true);
        if (!confirmed) {
          return;
        }
        try {
          await ref.read(chroniqueRepositoryProvider).delete(chronique.id);
          ref.read(upcomingChroniquesControllerProvider.notifier).removeById(chronique.id);
        } on ApiException catch (error) {
          if (!context.mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(messageForChroniqueApiError(error))),
          );
        } on FormatException {
          if (!context.mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unexpected error')),
          );
        }
      case ChroniqueCardMenuAction.archive:
        break;
    }
  }

  Widget _body(BuildContext context, WidgetRef ref, UpcomingChroniquesState state) {
    final colors = context.luminaColors;
    return switch (state) {
      UpcomingChroniquesLoading() => const AppLoading(),
      UpcomingChroniquesError(:final message) => _refreshable(
          ref: ref,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextTheme.bodyMedium.copyWith(color: colors.danger),
              ),
            ),
          ),
        ),
      UpcomingChroniquesReady(:final items) when items.isEmpty => _refreshable(
          ref: ref,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Text(
                'Aucune chronique programmée.',
                textAlign: TextAlign.center,
                style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        ),
      UpcomingChroniquesReady(:final items) => RefreshIndicator(
          onRefresh: () => _onRefresh(ref),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.xxl),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final item = items[index];
              return ChroniqueCard(
                chronique: item,
                excerpt: ChroniqueFields.excerpt(item.body),
                onTap: () => context.push(
                  AppRoutes.chroniqueDetail(item.id),
                  extra: item,
                ),
                onMenuSelected: (action) => _onMenu(context, ref, item, action),
              );
            },
          ),
        ),
    };
  }
}
