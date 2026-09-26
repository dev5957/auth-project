import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/chronique_assistant_copy.dart';

/// Options préparatoires (thème, commentaires, visibilité). Non envoyées à l’API.
class ChroniqueAssistantPausedOptions extends StatelessWidget {
  const ChroniqueAssistantPausedOptions({super.key});

  static const privateCategories = ['Famille', 'Amis', 'Collègues', 'Autres'];

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PausedSection(
          key: const ValueKey('assistant-theme'),
          title: 'Thème',
          child: Text(
            kChroniqueThemePausedMessage,
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        _PausedSection(
          key: const ValueKey('assistant-comments'),
          title: 'Commentaires',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                kChroniqueCommentsUnavailableMessage,
                style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              const _DisabledChoice(
                key: ValueKey('comments-yes'),
                label: 'Oui',
                selected: true,
              ),
              const _DisabledChoice(
                key: ValueKey('comments-no'),
                label: 'Non',
                selected: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        _PausedSection(
          key: const ValueKey('assistant-visibility'),
          title: 'Visibilité',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                kChroniqueVisibilityUnavailableMessage,
                style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              const _DisabledChoice(
                key: ValueKey('visibility-private'),
                label: 'Privé',
                selected: true,
              ),
              const _DisabledChoice(
                key: ValueKey('visibility-public'),
                label: 'Public',
                selected: false,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Catégories privées (non appliquées)',
                style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final label in privateCategories)
                    Chip(
                      key: ValueKey('assistant-category-$label'),
                      label: Text(label),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PausedSection extends StatelessWidget {
  const _PausedSection({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return AbsorbPointer(
      child: Opacity(
        opacity: 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: AppTextTheme.titleSmall.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

class _DisabledChoice extends StatelessWidget {
  const _DisabledChoice({
    super.key,
    required this.label,
    required this.selected,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: colors.textSecondary,
      ),
      title: Text(
        label,
        style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
      ),
      enabled: false,
    );
  }
}
