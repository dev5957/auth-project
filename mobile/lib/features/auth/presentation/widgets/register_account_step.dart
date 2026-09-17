import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_password_field.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../state/register_flow_controller.dart';

const int _loginMaxLength = 64;
const int _emailMaxLength = 254;
const int _passwordMinLength = 8;
const int _passwordMaxLength = 72;

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Étape 2 — Account. Pas d’appel API.
class RegisterAccountStep extends ConsumerStatefulWidget {
  const RegisterAccountStep({
    super.key,
    required this.onContinue,
  });

  final VoidCallback onContinue;

  @override
  ConsumerState<RegisterAccountStep> createState() => _RegisterAccountStepState();
}

class _RegisterAccountStepState extends ConsumerState<RegisterAccountStep> {
  late final TextEditingController _loginController;
  late final TextEditingController _emailController;
  late final TextEditingController _confirmEmailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmPasswordController;

  @override
  void initState() {
    super.initState();
    final data = ref.read(registerFlowProvider).data;
    _loginController = TextEditingController(text: data.login ?? '');
    _emailController = TextEditingController(text: data.email ?? '');
    _confirmEmailController = TextEditingController(text: data.confirmEmail ?? '');
    _passwordController = TextEditingController(text: data.password ?? '');
    _confirmPasswordController = TextEditingController(text: data.confirmPassword ?? '');
  }

  @override
  void dispose() {
    _loginController.dispose();
    _emailController.dispose();
    _confirmEmailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _nullableTrimmed(String raw) {
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  String? _nullablePassword(String raw) {
    return raw.isEmpty ? null : raw;
  }

  void _persist() {
    ref.read(registerFlowProvider.notifier).saveAccount(
          login: _nullableTrimmed(_loginController.text),
          email: _nullableTrimmed(_emailController.text),
          confirmEmail: _nullableTrimmed(_confirmEmailController.text),
          password: _nullablePassword(_passwordController.text),
          confirmPassword: _nullablePassword(_confirmPasswordController.text),
        );
  }

  String? get _loginError {
    final login = _loginController.text.trim();
    if (login.isEmpty) {
      return 'Login is required';
    }
    if (login.length > _loginMaxLength) {
      return 'login is invalid';
    }
    return null;
  }

  String? get _emailError {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      return 'Email is required';
    }
    if (email.length > _emailMaxLength || !_emailPattern.hasMatch(email)) {
      return 'email is invalid';
    }
    return null;
  }

  String? get _confirmEmailError {
    final email = _emailController.text.trim();
    final confirm = _confirmEmailController.text.trim();
    if (confirm.isEmpty) {
      return 'Confirm email is required';
    }
    if (email.toLowerCase() != confirm.toLowerCase()) {
      return 'Emails do not match';
    }
    return null;
  }

  String? get _passwordError {
    final password = _passwordController.text;
    if (password.isEmpty || password.trim().isEmpty) {
      return 'Password is required';
    }
    if (password.length < _passwordMinLength || password.length > _passwordMaxLength) {
      return 'Password must be between 8 and 72 characters';
    }
    return null;
  }

  String? get _confirmPasswordError {
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;
    if (confirm.isEmpty) {
      return 'Confirm password is required';
    }
    if (password != confirm) {
      return 'Passwords do not match';
    }
    return null;
  }

  bool get _canContinue =>
      _loginError == null &&
      _emailError == null &&
      _confirmEmailError == null &&
      _passwordError == null &&
      _confirmPasswordError == null;

  void _onChanged() {
    _persist();
    setState(() {});
  }

  void _onContinue() {
    if (!_canContinue) {
      return;
    }
    _persist();
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create your account',
            textAlign: TextAlign.center,
            style: AppTextTheme.titleLarge.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Step 2 of 4 · Account',
            textAlign: TextAlign.center,
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxxl),
          AppTextField(
            label: 'Login *',
            hint: 'Choose a login',
            controller: _loginController,
            errorText: _loginController.text.isEmpty ? null : _loginError,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_loginMaxLength),
            ],
            onChanged: (_) => _onChanged(),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Email *',
            hint: 'you@example.com',
            controller: _emailController,
            errorText: _emailController.text.isEmpty ? null : _emailError,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_emailMaxLength),
            ],
            onChanged: (_) => _onChanged(),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Confirm email *',
            hint: 'Re-enter your email',
            controller: _confirmEmailController,
            errorText: _confirmEmailController.text.isEmpty ? null : _confirmEmailError,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_emailMaxLength),
            ],
            onChanged: (_) => _onChanged(),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPasswordField(
            label: 'Password *',
            hint: '8–72 characters',
            controller: _passwordController,
            errorText: _passwordController.text.isEmpty ? null : _passwordError,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            onChanged: (_) => _onChanged(),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPasswordField(
            label: 'Confirm password *',
            hint: 'Re-enter your password',
            controller: _confirmPasswordController,
            errorText: _confirmPasswordController.text.isEmpty ? null : _confirmPasswordError,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) => _onContinue(),
            onChanged: (_) => _onChanged(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '* Required',
            style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxxl),
          AppButton(
            label: 'Continue',
            onPressed: _canContinue ? _onContinue : null,
          ),
        ],
      ),
    );
  }
}
