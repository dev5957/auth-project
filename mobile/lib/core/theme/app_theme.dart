import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text_theme.dart';

/// Thèmes Material 3 Lumina (clair / sombre).
class AppTheme {
  const AppTheme._();

  static const ThemeMode themeMode = ThemeMode.system;

  static ThemeData get light => _build(LuminaColors.light, Brightness.light);

  static ThemeData get dark => _build(LuminaColors.dark, Brightness.dark);

  static ThemeData _build(LuminaColors colors, Brightness brightness) {
    final textTheme = AppTextTheme.textTheme(color: colors.textPrimary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.bgBase,
      canvasColor: colors.bgBase,
      textTheme: textTheme,
      primaryTextTheme: AppTextTheme.textTheme(color: colors.textOnPrimary),
      colorScheme: (brightness == Brightness.light
              ? ColorScheme.light
              : ColorScheme.dark)(
        primary: colors.primary,
        onPrimary: colors.textOnPrimary,
        secondary: colors.secondary,
        onSecondary: colors.textOnPrimary,
        error: colors.danger,
        onError: colors.textOnPrimary,
        surface: colors.bgSurface,
        onSurface: colors.textPrimary,
        outline: colors.border,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.bgSurface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerColor: colors.border,
      extensions: <ThemeExtension<dynamic>>[colors],
    );
  }
}
