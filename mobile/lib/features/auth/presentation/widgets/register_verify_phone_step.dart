import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../state/register_flow_controller.dart';
import '../state/register_phone.dart';

const int _otpLength = 6;
const Duration _successPause = Duration(milliseconds: 1200);

/// Étape 4 — Verify phone. La requête passe par [onSubmit] (AuthController).
class RegisterVerifyPhoneStep extends ConsumerStatefulWidget {
  const RegisterVerifyPhoneStep({
    super.key,
    required this.onSubmit,
    required this.onVerified,
    required this.onChangePhoneNumber,
  });

  final Future<void> Function(String code) onSubmit;
  final VoidCallback onVerified;
  final VoidCallback onChangePhoneNumber;

  @override
  ConsumerState<RegisterVerifyPhoneStep> createState() =>
      _RegisterVerifyPhoneStepState();
}

class _RegisterVerifyPhoneStepState extends ConsumerState<RegisterVerifyPhoneStep> {
  final _cells = List<TextEditingController>.generate(
    _otpLength,
    (_) => TextEditingController(),
  );
  final _nodes = List<FocusNode>.generate(_otpLength, (_) => FocusNode());

  bool _submitting = false;
  bool _success = false;
  bool _applying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final node in _nodes) {
      node.addListener(_onFocusChange);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nodes.first.requestFocus();
      }
    });
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    for (final cell in _cells) {
      cell.dispose();
    }
    for (final node in _nodes) {
      node.removeListener(_onFocusChange);
      node.dispose();
    }
    super.dispose();
  }

  String get _code => _cells.map((cell) => cell.text).join();

  String _messageFor(ApiException error) {
    final message = error.message.trim();
    if (message.isNotEmpty) {
      return message;
    }
    switch (error.statusCode) {
      case 400:
        return 'Invalid verification code';
      case 404:
      case 410:
        return 'Verification token not found';
      case 409:
        return 'Email, login or phone number is already in use';
      case 429:
        return 'Too many requests';
      default:
        return 'Unexpected error';
    }
  }

  void _setCode(String digits) {
    _applying = true;
    final padded = digits.padRight(_otpLength).substring(0, _otpLength);
    for (var i = 0; i < _otpLength; i++) {
      final char = padded[i];
      final next = RegExp(r'^\d$').hasMatch(char) ? char : '';
      if (_cells[i].text != next) {
        _cells[i].value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    }
    _applying = false;
    final filled = _code.replaceAll(RegExp(r'[^0-9]'), '').length;
    final focusIndex = filled >= _otpLength ? _otpLength - 1 : filled;
    _nodes[focusIndex].requestFocus();
  }

  void _onCellChanged(int index, String raw) {
    if (_submitting || _success || _applying) {
      return;
    }
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    setState(() => _error = null);
    if (digits.length >= _otpLength) {
      _setCode(digits.substring(0, _otpLength));
      setState(() {});
      return;
    }
    if (digits.length > 1) {
      final merged = StringBuffer();
      for (var i = 0; i < index; i++) {
        merged.write(_cells[i].text);
      }
      merged.write(digits);
      _setCode(merged.toString());
      setState(() {});
      return;
    }
    if (digits.isEmpty) {
      _cells[index].value = const TextEditingValue(
        selection: TextSelection.collapsed(offset: 0),
      );
      setState(() {});
      return;
    }
    final digit = digits[digits.length - 1];
    _cells[index].value = TextEditingValue(
      text: digit,
      selection: const TextSelection.collapsed(offset: 1),
    );
    if (index < _otpLength - 1) {
      _nodes[index + 1].requestFocus();
    } else {
      _nodes[index].unfocus();
    }
    setState(() {});
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (_cells[index].text.isNotEmpty || index == 0) {
      return KeyEventResult.ignored;
    }
    _cells[index - 1].clear();
    _nodes[index - 1].requestFocus();
    setState(() => _error = null);
    return KeyEventResult.handled;
  }

  Future<void> _verify() async {
    if (_submitting || _success) {
      return;
    }
    final code = _code;
    if (code.length != _otpLength || !RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    final token = ref.read(registerFlowProvider).data.verificationToken;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Verification token is missing');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.onSubmit(code);
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _success = true;
      });
      await Future<void>.delayed(_successPause);
      if (!mounted) {
        return;
      }
      widget.onVerified();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = _messageFor(error);
      });
    } on FormatException {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = 'Unexpected error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final phone = ref.watch(
      registerFlowProvider.select((state) => state.data.phoneNumber),
    );
    final masked = (phone == null || phone.isEmpty)
        ? 'your phone'
        : maskRegisterPhoneNumber(phone);

    if (_success) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.check_circle_outline, size: 56, color: colors.success),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Phone verified',
            textAlign: TextAlign.center,
            style: AppTextTheme.titleLarge.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your account has been created.',
            textAlign: TextAlign.center,
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Verify your phone',
          textAlign: TextAlign.center,
          style: AppTextTheme.titleLarge.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Step 4 of 4 · Verify',
          textAlign: TextAlign.center,
          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'We sent a verification code to',
          textAlign: TextAlign.center,
          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          masked,
          textAlign: TextAlign.center,
          style: AppTextTheme.titleSmall.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        AutofillGroup(
          child: Row(
            children: [
              for (var i = 0; i < _otpLength; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _OtpCell(
                    index: i,
                    controller: _cells[i],
                    focusNode: _nodes[i],
                    enabled: !_submitting,
                    hasError: _error != null,
                    onChanged: (value) => _onCellChanged(i, value),
                    onKey: (event) => _onKey(i, event),
                    onSubmitted: i == _otpLength - 1 ? (_) => _verify() : null,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: AppTextTheme.labelSmall.copyWith(color: colors.danger),
          ),
        ],
        const SizedBox(height: AppSpacing.xxxl),
        AppButton(
          label: 'Verify',
          isLoading: _submitting,
          onPressed: _submitting ? null : _verify,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          "Didn't receive the code?",
          textAlign: TextAlign.center,
          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        ),
        TextButton(
          onPressed: null,
          child: Text(
            'Resend code',
            style: AppTextTheme.labelLarge.copyWith(
              color: colors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ),
        TextButton(
          onPressed: _submitting ? null : widget.onChangePhoneNumber,
          child: Text(
            'Change phone number',
            style: AppTextTheme.labelLarge.copyWith(color: colors.primary),
          ),
        ),
      ],
    );
  }
}

class _OtpCell extends StatelessWidget {
  const _OtpCell({
    required this.index,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hasError,
    required this.onChanged,
    required this.onKey,
    this.onSubmitted,
  });

  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final KeyEventResult Function(KeyEvent event) onKey;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final focused = focusNode.hasFocus;
    final borderColor = hasError
        ? colors.danger
        : focused
            ? colors.borderFocus
            : colors.border;

    return Focus(
      onKeyEvent: (node, event) => onKey(event),
      child: SizedBox(
        height: AppButton.height,
        child: TextField(
          key: ValueKey('otp-cell-$index'),
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          autofocus: index == 0,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          textInputAction:
              index == _otpLength - 1 ? TextInputAction.done : TextInputAction.next,
          autofillHints: index == 0 ? const [AutofillHints.oneTimeCode] : null,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          style: AppTextTheme.titleLarge.copyWith(color: colors.textPrimary),
          cursorColor: colors.borderFocus,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: colors.bgSurface,
            contentPadding: EdgeInsets.zero,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.lg),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.lg),
              borderSide: BorderSide(color: colors.borderFocus, width: 1.5),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.lg),
              borderSide: BorderSide(color: colors.border),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.lg),
              borderSide: BorderSide(color: colors.danger),
            ),
          ),
        ),
      ),
    );
  }
}
