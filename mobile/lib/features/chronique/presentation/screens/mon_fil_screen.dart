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
import '../../providers/chronique_providers.dart';
import '../state/mon_fil_controller.dart';
import '../widgets/chronique_card.dart';
import '../widgets/chronique_card_menu.dart';
import '../widgets/chronique_lifecycle_dialogs.dart';

/// Fil personnel V1. Route technique : `/explore`.
class MonFilScreen extends ConsumerWidget {
  const MonFilScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final state = ref.watch(monFilControllerProvider);

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        title: Text(
          'Mon Fil',
          style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
        ),
      ),
      body: SafeArea(child: _body(context, ref, state)),
    );
  }

  Future<void> _onRefresh(WidgetRef ref) {
    return ref.read(monFilControllerProvider.notifier).refresh();
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
          ref.read(monFilControllerProvider.notifier).upsert(updated);
        }
      case ChroniqueCardMenuAction.archive:
        final confirmed = await confirmArchiveChronique(context);
        if (!confirmed) {
          return;
        }
        try {
          await ref.read(chroniqueRepositoryProvider).archive(chronique.id);
          ref.read(monFilControllerProvider.notifier).removeById(chronique.id);
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
      case ChroniqueCardMenuAction.delete:
        final confirmed = await confirmDeleteChronique(
          context,
          scheduled: chronique.status == 'scheduled',
        );
        if (!confirmed) {
          return;
        }
        try {
          await ref.read(chroniqueRepositoryProvider).delete(chronique.id);
          ref.read(monFilControllerProvider.notifier).removeById(chronique.id);
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
    }
  }

  Widget _refreshable({
    required WidgetRef ref,
    required Widget child,
    bool alwaysScrollable = false,
  }) {
    return RefreshIndicator(
      onRefresh: () => _onRefresh(ref),
      child: alwaysScrollable
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 360,
                  child: child,
                ),
              ],
            )
          : child,
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, MonFilState state) {
    final colors = context.luminaColors;
    return switch (state) {
      MonFilLoading() => const AppLoading(),
      MonFilError(:final message) => _refreshable(
          ref: ref,
          alwaysScrollable: true,
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
      MonFilReady(:final items) when items.isEmpty => _refreshable(
          ref: ref,
          alwaysScrollable: true,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Text(
                'Aucune chronique pour le moment.',
                textAlign: TextAlign.center,
                style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        ),
      MonFilReady(:final items) => RefreshIndicator(
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
