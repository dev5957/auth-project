import 'package:flutter/material.dart';

/// Échelle typographique mobile (Android / iOS). Pas de police custom.
class AppTextTheme {
  const AppTextTheme._();

  static const TextStyle display = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: -0.4,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: -0.2,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.1,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: 0.2,
  );

  static TextTheme textTheme({required Color color}) {
    TextStyle withColor(TextStyle style) => style.copyWith(color: color);

    final displayStyle = withColor(display);
    final titleLargeStyle = withColor(titleLarge);
    final bodyMediumStyle = withColor(bodyMedium);
    final labelLargeStyle = withColor(labelLarge);

    return TextTheme(
      displayLarge: displayStyle,
      displayMedium: displayStyle,
      displaySmall: withColor(titleLarge),
      headlineLarge: titleLargeStyle,
      headlineMedium: withColor(titleMedium),
      headlineSmall: withColor(titleSmall),
      titleLarge: titleLargeStyle,
      titleMedium: withColor(titleMedium),
      titleSmall: withColor(titleSmall),
      bodyLarge: withColor(bodyLarge),
      bodyMedium: bodyMediumStyle,
      bodySmall: bodyMediumStyle,
      labelLarge: labelLargeStyle,
      labelMedium: labelLargeStyle,
      labelSmall: withColor(labelSmall),
    );
  }
}
