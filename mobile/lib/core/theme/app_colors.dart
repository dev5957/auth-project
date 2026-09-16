import 'package:flutter/material.dart';

/// Tokens sémantiques Lumina. Les widgets doivent lire ceci, pas `Colors.*`.
@immutable
class LuminaColors extends ThemeExtension<LuminaColors> {
  const LuminaColors({
    required this.primary,
    required this.primaryPressed,
    required this.secondary,
    required this.success,
    required this.danger,
    required this.warning,
    required this.bgBase,
    required this.bgSurface,
    required this.bgRaised,
    required this.textPrimary,
    required this.textSecondary,
    required this.textOnPrimary,
    required this.border,
    required this.borderFocus,
  });

  final Color primary;
  final Color primaryPressed;
  final Color secondary;
  final Color success;
  final Color danger;
  final Color warning;
  final Color bgBase;
  final Color bgSurface;
  final Color bgRaised;
  final Color textPrimary;
  final Color textSecondary;
  final Color textOnPrimary;
  final Color border;
  final Color borderFocus;

  static const LuminaColors light = LuminaColors(
    primary: Color(0xFF5B4BFF),
    primaryPressed: Color(0xFF4338CA),
    secondary: Color(0xFF0F766E),
    success: Color(0xFF15803D),
    danger: Color(0xFFDC2626),
    warning: Color(0xFFD97706),
    bgBase: Color(0xFFF8FAFC),
    bgSurface: Color(0xFFFFFFFF),
    bgRaised: Color(0xFFF1F5F9),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF64748B),
    textOnPrimary: Color(0xFFFFFFFF),
    border: Color(0xFFE2E8F0),
    borderFocus: Color(0xFF5B4BFF),
  );

  static const LuminaColors dark = LuminaColors(
    primary: Color(0xFF818CF8),
    primaryPressed: Color(0xFF6366F1),
    secondary: Color(0xFF2DD4BF),
    success: Color(0xFF4ADE80),
    danger: Color(0xFFF87171),
    warning: Color(0xFFFBBF24),
    bgBase: Color(0xFF0B1220),
    bgSurface: Color(0xFF111827),
    bgRaised: Color(0xFF1F2937),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    textOnPrimary: Color(0xFF0F172A),
    border: Color(0xFF334155),
    borderFocus: Color(0xFF818CF8),
  );

  @override
  LuminaColors copyWith({
    Color? primary,
    Color? primaryPressed,
    Color? secondary,
    Color? success,
    Color? danger,
    Color? warning,
    Color? bgBase,
    Color? bgSurface,
    Color? bgRaised,
    Color? textPrimary,
    Color? textSecondary,
    Color? textOnPrimary,
    Color? border,
    Color? borderFocus,
  }) {
    return LuminaColors(
      primary: primary ?? this.primary,
      primaryPressed: primaryPressed ?? this.primaryPressed,
      secondary: secondary ?? this.secondary,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      bgBase: bgBase ?? this.bgBase,
      bgSurface: bgSurface ?? this.bgSurface,
      bgRaised: bgRaised ?? this.bgRaised,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textOnPrimary: textOnPrimary ?? this.textOnPrimary,
      border: border ?? this.border,
      borderFocus: borderFocus ?? this.borderFocus,
    );
  }

  @override
  LuminaColors lerp(ThemeExtension<LuminaColors>? other, double t) {
    if (other is! LuminaColors) {
      return this;
    }
    return LuminaColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryPressed: Color.lerp(primaryPressed, other.primaryPressed, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      bgBase: Color.lerp(bgBase, other.bgBase, t)!,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t)!,
      bgRaised: Color.lerp(bgRaised, other.bgRaised, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textOnPrimary: Color.lerp(textOnPrimary, other.textOnPrimary, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t)!,
    );
  }
}

extension LuminaColorsContext on BuildContext {
  LuminaColors get luminaColors => Theme.of(this).extension<LuminaColors>()!;
}
