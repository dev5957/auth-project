import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/media_draft.dart';
import 'media_draft_list.dart';

/// Choix de type média. La galerie / le sélecteur système s’ouvrent ensuite.
Future<MediaDraftKind?> showAddMediaKindSheet(BuildContext context) {
  return showModalBottomSheet<MediaDraftKind>(
    context: context,
    builder: (context) {
      final colors = context.luminaColors;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final kind in MediaDraftKind.values)
                ListTile(
                  title: Text(
                    mediaDraftKindLabel(kind),
                    style: AppTextTheme.bodyLarge.copyWith(color: colors.textPrimary),
                  ),
                  onTap: () => Navigator.of(context).pop(kind),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Après « Image » : galerie ou appareil photo.
Future<MediaDraftSourceType?> showAddImageSourceSheet(BuildContext context) {
  return showModalBottomSheet<MediaDraftSourceType>(
    context: context,
    builder: (context) {
      final colors = context.luminaColors;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'Galerie (plusieurs)',
                  style: AppTextTheme.bodyLarge.copyWith(color: colors.textPrimary),
                ),
                onTap: () => Navigator.of(context).pop(MediaDraftSourceType.gallery),
              ),
              ListTile(
                title: Text(
                  'Appareil photo',
                  style: AppTextTheme.bodyLarge.copyWith(color: colors.textPrimary),
                ),
                onTap: () => Navigator.of(context).pop(MediaDraftSourceType.camera),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Après « Vidéo » : galerie ou caméra.
Future<MediaDraftSourceType?> showAddVideoSourceSheet(BuildContext context) {
  return showModalBottomSheet<MediaDraftSourceType>(
    context: context,
    builder: (context) {
      final colors = context.luminaColors;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'Galerie (plusieurs)',
                  style: AppTextTheme.bodyLarge.copyWith(color: colors.textPrimary),
                ),
                onTap: () => Navigator.of(context).pop(MediaDraftSourceType.gallery),
              ),
              ListTile(
                title: Text(
                  'Caméra',
                  style: AppTextTheme.bodyLarge.copyWith(color: colors.textPrimary),
                ),
                onTap: () => Navigator.of(context).pop(MediaDraftSourceType.camera),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Après « Audio » : fichier ou microphone.
Future<MediaDraftSourceType?> showAddAudioSourceSheet(BuildContext context) {
  return showModalBottomSheet<MediaDraftSourceType>(
    context: context,
    builder: (context) {
      final colors = context.luminaColors;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'Fichier',
                  style: AppTextTheme.bodyLarge.copyWith(color: colors.textPrimary),
                ),
                onTap: () => Navigator.of(context).pop(MediaDraftSourceType.upload),
              ),
              ListTile(
                title: Text(
                  'Microphone',
                  style: AppTextTheme.bodyLarge.copyWith(color: colors.textPrimary),
                ),
                onTap: () => Navigator.of(context).pop(MediaDraftSourceType.microphone),
              ),
            ],
          ),
        ),
      );
    },
  );
}
