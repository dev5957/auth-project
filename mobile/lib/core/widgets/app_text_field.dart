import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

/// Champ texte Lumina (login, email, téléphone, nom, date de naissance).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.errorText,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.focusNode,
    this.enabled = true,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.textCapitalization = TextCapitalization.none,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.inputFormatters,
    this.readOnly = false,
    this.minLines,
    this.maxLines = 1,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? errorText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;
  final bool enabled;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextCapitalization textCapitalization;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;
  final int? minLines;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final rawError = errorText;
    final resolvedError =
        (rawError == null || rawError.isEmpty) ? null : rawError;

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.lg),
      borderSide: BorderSide(color: colors.border),
    );

    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscureText,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      textCapitalization: textCapitalization,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      readOnly: readOnly,
      minLines: minLines,
      maxLines: maxLines,
      textAlignVertical:
          (maxLines ?? 1) == 1 ? TextAlignVertical.center : TextAlignVertical.top,
      style: AppTextTheme.bodyLarge.copyWith(color: colors.textPrimary),
      cursorColor: colors.borderFocus,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: resolvedError,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: colors.bgSurface,
        labelStyle: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        hintStyle: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        errorStyle: AppTextTheme.labelSmall.copyWith(color: colors.danger),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.lg),
          borderSide: BorderSide(color: colors.borderFocus, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.lg),
          borderSide: BorderSide(color: colors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.lg),
          borderSide: BorderSide(color: colors.danger, width: 1.5),
        ),
      ),
    );
  }
}
