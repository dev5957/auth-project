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
import '../state/archives_controller.dart';
import '../widgets/chronique_card.dart';
import '../widgets/chronique_card_menu.dart';
import '../widgets/chronique_lifecycle_dialogs.dart';

/// Archives volontaires : `GET /chroniques?status=archived`.
class ArchivesScreen extends ConsumerStatefulWidget {
  const ArchivesScreen({super.key});

  @override
  ConsumerState<ArchivesScreen> createState() => _ArchivesScreenState();
}

class _ArchivesScreenState extends ConsumerState<ArchivesScreen> {
  bool _busy = false;

  Future<void> _onRefresh() {
    return ref.read(archivesControllerProvider.notifier).refresh();
  }

  Widget _refreshable({required Widget child}) {
    return RefreshIndicator(
      onRefresh: _onRefresh,
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

  Future<void> _onMenu(Chronique chronique, ChroniqueCardMenuAction action) async {
    if (_busy) {
      return;
    }
    switch (action) {
      case ChroniqueCardMenuAction.edit:
      case ChroniqueCardMenuAction.archive:
        break;
      case ChroniqueCardMenuAction.delete:
        final confirmed = await confirmDeleteChronique(
          context,
          scheduled: false,
          fromArchives: true,
        );
        if (!confirmed || !mounted) {
          return;
        }
        setState(() {
          _busy = true;
        });
        try {
          await ref.read(chroniqueRepositoryProvider).delete(chronique.id);
          if (!mounted) {
            return;
          }
          ref.read(archivesControllerProvider.notifier).removeById(chronique.id);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chronique supprimée')),
          );
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
        } finally {
          if (mounted) {
            setState(() {
              _busy = false;
            });
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: SafeArea(child: _body(context, colors, state)),
    );
  }

  Widget _body(BuildContext context, LuminaColors colors, ArchivesState state) {
    return switch (state) {
      ArchivesLoading() => const AppLoading(),
      ArchivesError(:final message) => _refreshable(
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
          onRefresh: _onRefresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.xxl),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final item = items[index];
              return ChroniqueCard(
                chronique: item,
                onTap: _busy
                    ? null
                    : () => context.push(
                          AppRoutes.chroniqueDetail(item.id),
                          extra: item,
                        ),
                onMenuSelected: _busy ? null : (action) => _onMenu(item, action),
              );
            },
          ),
        ),
    };
  }
}
