import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/app_password_field.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../providers/auth_controller.dart';
import '../state/forgot_password_flow_controller.dart';

class ForgotPasswordScreen extends ConsumerWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final step = ref.watch(forgotPasswordFlowProvider.select((state) => state.step));

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            final current = ref.read(forgotPasswordFlowProvider).step;
            if (current == ForgotPasswordStep.email) {
              context.pop();
              return;
            }
            ref.read(forgotPasswordFlowProvider.notifier).goToPreviousStep();
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AppLogo(size: 56)),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Forgot password',
                textAlign: TextAlign.center,
                style: AppTextTheme.titleLarge.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xxl),
              switch (step) {
                ForgotPasswordStep.email => const _ForgotEmailStep(),
                ForgotPasswordStep.code => const _ForgotCodeStep(),
                ForgotPasswordStep.password => const _ForgotPasswordStep(),
              },
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

String _apiMessage(ApiException error) {
  final message = error.message.trim();
  if (message.isNotEmpty) {
    return message;
  }
  if (error.statusCode == 429) {
    return 'Too many requests';
  }
  return 'Unexpected error';
}

class _ForgotEmailStep extends ConsumerStatefulWidget {
  const _ForgotEmailStep();

  @override
  ConsumerState<_ForgotEmailStep> createState() => _ForgotEmailStepState();
}

class _ForgotEmailStepState extends ConsumerState<_ForgotEmailStep> {
  late final TextEditingController _emailController;
  bool _submitting = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(
      text: ref.read(forgotPasswordFlowProvider).email,
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      setState(() => _formError = 'Email is required');
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
    });
    try {
      final message = await ref.read(authControllerProvider.notifier).requestPasswordReset(
            email: email,
          );
      if (!mounted) {
        return;
      }
      ref.read(forgotPasswordFlowProvider.notifier).saveEmail(
            email: email,
            genericMessage: message,
          );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _formError = _apiMessage(error));
    } on FormatException {
      if (!mounted) {
        return;
      }
      setState(() => _formError = 'Unexpected error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the email of your Lumina account. If an account exists, we will send a reset code.',
          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Email',
          hint: 'you@example.com',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          enabled: !_submitting,
          onChanged: (_) {
            if (_formError != null) {
              setState(() => _formError = null);
            }
          },
        ),
        if (_formError != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _formError!,
            textAlign: TextAlign.center,
            style: AppTextTheme.labelSmall.copyWith(color: colors.danger),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        AppButton(
          label: 'Send reset code',
          isLoading: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

class _ForgotCodeStep extends ConsumerStatefulWidget {
  const _ForgotCodeStep();

  @override
  ConsumerState<_ForgotCodeStep> createState() => _ForgotCodeStepState();
}

class _ForgotCodeStepState extends ConsumerState<_ForgotCodeStep> {
  late final TextEditingController _codeController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(
      text: ref.read(forgotPasswordFlowProvider).code ?? '',
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _continue() {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    ref.read(forgotPasswordFlowProvider.notifier).saveCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final message = ref.watch(forgotPasswordFlowProvider.select((state) => state.genericMessage));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null && message.isNotEmpty) ...[
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Text(
          'Enter the code',
          style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Reset code',
          hint: '123456',
          controller: _codeController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onChanged: (_) {
            if (_error != null) {
              setState(() => _error = null);
            }
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: AppTextTheme.labelSmall.copyWith(color: colors.danger),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        AppButton(
          label: 'Continue',
          onPressed: _continue,
        ),
      ],
    );
  }
}

class _ForgotPasswordStep extends ConsumerStatefulWidget {
  const _ForgotPasswordStep();

  @override
  ConsumerState<_ForgotPasswordStep> createState() => _ForgotPasswordStepState();
}

class _ForgotPasswordStepState extends ConsumerState<_ForgotPasswordStep> {
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmController;
  bool _submitting = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _passwordController = TextEditingController();
    _confirmController = TextEditingController();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (password.length < 8 || password.length > 72) {
      setState(() => _formError = 'Password must be between 8 and 72 characters');
      return;
    }
    if (password != confirm) {
      setState(() => _formError = 'password and password_confirmation do not match');
      return;
    }
    final flow = ref.read(forgotPasswordFlowProvider);
    final code = flow.code;
    if (code == null || flow.email.isEmpty) {
      setState(() => _formError = 'Complete the previous steps');
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).confirmPasswordReset(
            email: flow.email,
            code: code,
            password: password,
            passwordConfirmation: confirm,
          );
      if (!mounted) {
        return;
      }
      ref.read(forgotPasswordFlowProvider.notifier).reset();
      context.go(AppRoutes.login);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _formError = _apiMessage(error));
    } on FormatException {
      if (!mounted) {
        return;
      }
      setState(() => _formError = 'Unexpected error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose a new password',
          style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppPasswordField(
          label: 'New password',
          hint: '8–72 characters',
          controller: _passwordController,
          enabled: !_submitting,
          onChanged: (_) {
            if (_formError != null) {
              setState(() => _formError = null);
            }
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        AppPasswordField(
          label: 'Confirm password',
          hint: 'Re-enter your password',
          controller: _confirmController,
          enabled: !_submitting,
          onChanged: (_) {
            if (_formError != null) {
              setState(() => _formError = null);
            }
          },
        ),
        if (_formError != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _formError!,
            textAlign: TextAlign.center,
            style: AppTextTheme.labelSmall.copyWith(color: colors.danger),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        AppButton(
          label: 'Reset password',
          isLoading: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}
