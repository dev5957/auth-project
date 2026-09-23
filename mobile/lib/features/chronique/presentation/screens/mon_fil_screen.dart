import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_loading.dart';
import '../state/mon_fil_controller.dart';
import '../widgets/chronique_card.dart';

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
      body: SafeArea(child: _body(context, state)),
    );
  }

  Widget _body(BuildContext context, MonFilState state) {
    final colors = context.luminaColors;
    return switch (state) {
      MonFilLoading() => const AppLoading(),
      MonFilError(:final message) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextTheme.bodyMedium.copyWith(color: colors.danger),
            ),
          ),
        ),
      MonFilReady(:final items) when items.isEmpty => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Text(
              'Aucune chronique pour le moment.',
              textAlign: TextAlign.center,
              style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
            ),
          ),
        ),
      MonFilReady(:final items) => ListView.separated(
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
    };
  }
}
