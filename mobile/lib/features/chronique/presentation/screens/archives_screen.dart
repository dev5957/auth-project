import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_loading.dart';
import '../state/archives_controller.dart';
import '../widgets/chronique_card.dart';

/// Archives volontaires : `GET /chroniques?status=archived`.
class ArchivesScreen extends ConsumerWidget {
  const ArchivesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final state = ref.watch(archivesControllerProvider);

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        title: Text(
          'Archives',
          style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
        ),
      ),
      body: SafeArea(child: _body(context, ref, state)),
    );
  }

  Future<void> _onRefresh(WidgetRef ref) {
    return ref.read(archivesControllerProvider.notifier).refresh();
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

  Widget _body(BuildContext context, WidgetRef ref, ArchivesState state) {
    final colors = context.luminaColors;
    return switch (state) {
      ArchivesLoading() => const AppLoading(),
      ArchivesError(:final message) => _refreshable(
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
      ArchivesReady(:final items) when items.isEmpty => _refreshable(
          ref: ref,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Text(
                'Aucune chronique archivée.',
                textAlign: TextAlign.center,
                style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        ),
      ArchivesReady(:final items) => RefreshIndicator(
          onRefresh: () => _onRefresh(ref),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.xxl),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              return ChroniqueCard(
                chronique: items[index],
                onTap: () => context.push(
                  AppRoutes.chroniqueDetail(items[index].id),
                  extra: items[index],
                ),
              );
            },
          ),
        ),
    };
  }
}
