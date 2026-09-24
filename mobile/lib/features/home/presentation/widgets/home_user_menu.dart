import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../home_user_initials.dart';

const String kSoonAvailableMessage = 'Bientôt disponible';

/// Menu utilisateur (avatar Home). Logout = callback existant.
Future<void> showHomeUserMenu(
  BuildContext context, {
  required String login,
  required VoidCallback onUpcoming,
  required VoidCallback onArchives,
  required VoidCallback onLogout,
}) {
  final colors = context.luminaColors;
  final initials = homeUserInitials(login);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: colors.bgRaised,
                  foregroundColor: colors.primary,
                  child: Text(
                    initials.isEmpty ? '?' : initials,
                    style: AppTextTheme.labelLarge.copyWith(color: colors.primary),
                  ),
                ),
                title: Text(
                  login,
                  style: AppTextTheme.titleSmall.copyWith(color: colors.textPrimary),
                ),
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.schedule, color: colors.textPrimary),
                title: const Text('🕒 À venir'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onUpcoming();
                },
              ),
              ListTile(
                leading: Icon(Icons.folder_outlined, color: colors.textPrimary),
                title: const Text('Archives'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onArchives();
                },
              ),
              ListTile(
                leading: Icon(Icons.person_outline, color: colors.textPrimary),
                title: const Text('Profil'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showSoon(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.settings_outlined, color: colors.textPrimary),
                title: const Text('Paramètres'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showSoon(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.lock_outline, color: colors.textPrimary),
                title: const Text('Sécurité'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showSoon(context);
                },
              ),
              ListTile(
                key: const ValueKey('home-logout'),
                leading: Icon(Icons.logout, color: colors.textPrimary),
                title: const Text('Déconnexion'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onLogout();
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _showSoon(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text(kSoonAvailableMessage)),
  );
}
