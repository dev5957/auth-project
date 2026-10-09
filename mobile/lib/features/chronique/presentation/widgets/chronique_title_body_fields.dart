import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../models/chronique_fields.dart';

/// Titre + corps réutilisés par l’édition programmée et l’espace auteur.
class ChroniqueTitleBodyFields extends StatelessWidget {
  const ChroniqueTitleBodyFields({
    super.key,
    required this.titleController,
    required this.bodyController,
    this.titleError,
    this.bodyError,
    this.enabled = true,
  });

  final TextEditingController titleController;
  final TextEditingController bodyController;
  final String? titleError;
  final String? bodyError;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final bodyCount = ChroniqueFields.runeLength(bodyController.text.trim());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Titre (optionnel)',
          hint: 'Titre',
          controller: titleController,
          errorText: titleError,
          enabled: enabled,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Texte *',
          hint: 'Votre texte',
          controller: bodyController,
          errorText: bodyError,
          enabled: enabled,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textCapitalization: TextCapitalization.sentences,
          minLines: 6,
          maxLines: 12,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '$bodyCount / ${ChroniqueFields.bodyMax}',
          textAlign: TextAlign.right,
          style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}
