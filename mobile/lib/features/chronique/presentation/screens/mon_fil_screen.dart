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
import '../widgets/chronique_media_viewer.dart';
import 'chronique_detail_screen.dart';

/// Fil personnel V1. Route technique : `/explore`.
class MonFilScreen extends ConsumerStatefulWidget {
  const MonFilScreen({super.key});

  @override
  ConsumerState<MonFilScreen> createState() => _MonFilScreenState();
}

class _MonFilScreenState extends ConsumerState<MonFilScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() {
    return ref.read(monFilControllerProvider.notifier).refresh();
  }

  Future<void> _openDetail(Chronique chronique) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ChroniqueDetailScreen(
          chroniqueId: chronique.id,
          chronique: chronique,
        ),
      ),
    );
  }

  Future<void> _onMenu(Chronique chronique, ChroniqueCardMenuAction action) async {
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
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(messageForChroniqueApiError(error))),
          );
        } on FormatException {
          if (!mounted) {
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
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(messageForChroniqueApiError(error))),
          );
        } on FormatException {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unexpected error')),
          );
        }
    }
  }

  Widget _refreshable({
    required Widget child,
    bool alwaysScrollable = false,
  }) {
    return RefreshIndicator(
      onRefresh: _onRefresh,
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

  @override
  Widget build(BuildContext context) {
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
      body: SafeArea(child: _body(colors, state)),
    );
  }

  Widget _body(LuminaColors colors, MonFilState state) {
    return switch (state) {
      MonFilLoading() => const AppLoading(),
      MonFilError(:final message) => _refreshable(
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
          onRefresh: _onRefresh,
          child: ListView.separated(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.xxl),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final item = items[index];
              return ChroniqueCard(
                chronique: item,
                showFeedMedia: true,
                showInactiveSocialActions: true,
                onTap: () => _openDetail(item),
                onMediaSelected: (media) => openChroniqueFeedMedia(context, media),
                onMenuSelected: (action) => _onMenu(item, action),
              );
            },
          ),
        ),
    };
  }
}
