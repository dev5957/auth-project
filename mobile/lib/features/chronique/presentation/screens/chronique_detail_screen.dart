import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/chronique.dart';
import '../state/mon_fil_controller.dart';
import '../widgets/chronique_card.dart';

/// Lecture détaillée V1. Pas de médias ni d’actions sociales.
class ChroniqueDetailScreen extends ConsumerWidget {
  const ChroniqueDetailScreen({
    super.key,
    required this.chroniqueId,
    this.chronique,
  });

  final int? chroniqueId;
  final Chronique? chronique;

  Chronique? _resolve(MonFilState state) {
    if (chronique != null) {
      return chronique;
    }
    if (chroniqueId == null || state is! MonFilReady) {
      return null;
    }
    for (final item in state.items) {
      if (item.id == chroniqueId) {
        return item;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final resolved = _resolve(ref.watch(monFilControllerProvider));
    final dateLabel = resolved == null ? '' : chroniqueDateLabel(resolved);
    final title = resolved?.title?.trim();

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        title: Text(
          title != null && title.isNotEmpty ? title : 'Chronique',
          style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: resolved == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Text(
                    'Chronique introuvable',
                    textAlign: TextAlign.center,
                    style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (dateLabel.isNotEmpty) ...[
                      Text(
                        dateLabel,
                        style: AppTextTheme.labelSmall.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    if (title != null && title.isNotEmpty) ...[
                      Text(
                        title,
                        style: AppTextTheme.titleLarge.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    Text(
                      resolved.body,
                      style: AppTextTheme.bodyLarge.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
