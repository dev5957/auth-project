import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_loading.dart';
import '../state/expired_chroniques_controller.dart';
import '../widgets/chronique_card.dart';
import '../widgets/chronique_media_viewer.dart';

/// Chroniques éphémères expirées encore en rétention : `GET /chroniques?status=expired`.
class ExpiredChroniquesScreen extends ConsumerWidget {
  const ExpiredChroniquesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final state = ref.watch(expiredChroniquesControllerProvider);

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        title: Text(
          'Chroniques expirées',
          style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
        ),
      ),
      body: SafeArea(child: _body(context, ref, state)),
    );
  }

  Future<void> _onRefresh(WidgetRef ref) {
    return ref.read(expiredChroniquesControllerProvider.notifier).refresh();
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

  Widget _body(BuildContext context, WidgetRef ref, ExpiredChroniquesState state) {
    final colors = context.luminaColors;
    return switch (state) {
      ExpiredChroniquesLoading() => const AppLoading(),
      ExpiredChroniquesError(:final message) => _refreshable(
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
      ExpiredChroniquesReady(:final items) when items.isEmpty => _refreshable(
          ref: ref,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Text(
                'Aucune chronique expirée.',
                textAlign: TextAlign.center,
                style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        ),
      ExpiredChroniquesReady(:final items) => RefreshIndicator(
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
                showFeedMedia: true,
                onMediaSelected: (media) => openChroniqueFeedMedia(context, media),
                onTap: () => context.push(
                  AppRoutes.chroniqueDetail(item.id),
                  extra: item,
                ),
              );
            },
          ),
        ),
    };
  }
}
