import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';

/// Options locales (thème, commentaires, visibilité). Non envoyées à l’API.
class ChroniqueAssistantPausedOptions extends StatefulWidget {
  const ChroniqueAssistantPausedOptions({super.key});

  static const privateCategories = ['Famille', 'Amis', 'Collègues', 'Autres'];

  @override
  State<ChroniqueAssistantPausedOptions> createState() =>
      _ChroniqueAssistantPausedOptionsState();
}

class _ChroniqueAssistantPausedOptionsState
    extends State<ChroniqueAssistantPausedOptions> {
  bool _commentsEnabled = true;
  bool _private = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const ValueKey('assistant-theme'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Thèmes',
            style: AppTextTheme.titleSmall.copyWith(color: colors.textPrimary),
          ),
          trailing: Icon(Icons.chevron_right, color: colors.textSecondary),
          onTap: () {},
        ),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          'Commentaires',
          key: const ValueKey('assistant-comments'),
          style: AppTextTheme.titleSmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Choice(
          key: const ValueKey('comments-yes'),
          label: 'Oui',
          selected: _commentsEnabled,
          onTap: () => setState(() => _commentsEnabled = true),
        ),
        _Choice(
          key: const ValueKey('comments-no'),
          label: 'Non',
          selected: !_commentsEnabled,
          onTap: () => setState(() => _commentsEnabled = false),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          'Visibilité',
          key: const ValueKey('assistant-visibility'),
          style: AppTextTheme.titleSmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Choice(
          key: const ValueKey('visibility-public'),
          label: 'Public',
          selected: !_private,
          onTap: () => setState(() => _private = false),
        ),
        _Choice(
          key: const ValueKey('visibility-private'),
          label: 'Privé',
          selected: _private,
          onTap: () => setState(() => _private = true),
        ),
        if (_private) ...[
          const SizedBox(height: AppSpacing.md),
          for (final label in ChroniqueAssistantPausedOptions.privateCategories)
            _Choice(
              key: ValueKey('assistant-category-$label'),
              label: label,
              selected: false,
              onTap: () {},
            ),
        ],
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: colors.primary,
      ),
      title: Text(
        label,
        style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
      ),
    );
  }
}
