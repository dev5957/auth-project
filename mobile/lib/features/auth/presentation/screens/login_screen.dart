import 'package:flutter/material.dart';
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
import '../state/register_flow_controller.dart';

/// Écran Sign in. Passe uniquement par [AuthController.login].
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _loginError;
  String? _passwordError;
  String? _formError;
  bool _submitting = false;

  @override
  void dispose() {
    debugPrint(
      '[auth-login-diag] LoginScreen.dispose() isLoading=$_submitting',
    );
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _validate() {
    final login = _loginController.text.trim();
    final password = _passwordController.text;
    final loginError = login.isEmpty ? 'Login is required' : null;
    final passwordError = password.isEmpty ? 'Password is required' : null;
    setState(() {
      _loginError = loginError;
      _passwordError = passwordError;
      _formError = null;
    });
    return loginError == null && passwordError == null;
  }

  String _messageFor(ApiException error) {
    final message = error.message.trim();
    if (message.isNotEmpty) {
      return message;
    }
    switch (error.statusCode) {
      case 401:
        return 'Incorrect login or password';
      case 403:
        return 'Phone number is not verified';
      case 429:
        return 'Too many requests';
      default:
        return 'Unexpected error';
    }
  }

  Future<void> _submit() async {
    debugPrint(
      '[auth-login-diag] LoginScreen._submit() entered '
      'isLoading=$_submitting mounted=$mounted',
    );
    if (_submitting) {
      debugPrint(
        '[auth-login-diag] LoginScreen._submit() aborted already submitting '
        'isLoading=$_submitting',
      );
      return;
    }
    if (!_validate()) {
      debugPrint(
        '[auth-login-diag] LoginScreen._submit() aborted validation failed '
        'isLoading=$_submitting',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
    });
    debugPrint(
      '[auth-login-diag] LoginScreen button pressed → isLoading before=false after=$_submitting',
    );
    debugPrint('[auth-http-diag][B] LoginScreen Sign in tapped');
    debugPrint('[auth-login-diag] LoginScreen calling AuthController.login()');
    try {
      await ref.read(authControllerProvider.notifier).login(
            login: _loginController.text.trim(),
            password: _passwordController.text,
          );
      debugPrint(
        '[auth-http-diag][B] LoginScreen after login() '
        'auth=${ref.read(authControllerProvider).runtimeType} mounted=$mounted',
      );
      debugPrint(
        '[auth-login-diag] LoginScreen after AuthController.login() '
        'auth=${ref.read(authControllerProvider).runtimeType} '
        'isLoading=$_submitting mounted=$mounted',
      );
      if (!mounted) {
        debugPrint('[auth-http-diag][B] LoginScreen unmounted, skip context.go(/home)');
        debugPrint(
          '[auth-login-diag] LoginScreen unmounted after login() — flow left Login',
        );
        return;
      }
      debugPrint('[auth-http-diag][B] LoginScreen context.go(/home)');
      debugPrint('[auth-login-diag] LoginScreen context.go(${AppRoutes.home})');
      context.go(AppRoutes.home);
    } on ApiException catch (error) {
      debugPrint(
        '[auth-http-diag][B] LoginScreen ApiException statusCode=${error.statusCode}',
      );
      debugPrint(
        '[auth-login-diag] LoginScreen caught ApiException '
        'statusCode=${error.statusCode} mounted=$mounted',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _formError = _messageFor(error);
      });
    } on FormatException {
      debugPrint('[auth-login-diag] LoginScreen caught FormatException mounted=$mounted');
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _formError = 'Unexpected error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: AutofillGroup(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xl),
                const Center(child: AppLogo(size: 72)),
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  'Welcome back',
                  textAlign: TextAlign.center,
                  style: AppTextTheme.titleLarge.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Sign in to continue to Lumina.',
                  textAlign: TextAlign.center,
                  style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xxxl),
                AppTextField(
                  label: 'Login',
                  hint: 'Your login',
                  controller: _loginController,
                  errorText: _loginError,
                  enabled: !_submitting,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) {
                    if (_loginError != null) {
                      setState(() => _loginError = null);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                AppPasswordField(
                  label: 'Password',
                  hint: 'Your password',
                  controller: _passwordController,
                  errorText: _passwordError,
                  enabled: !_submitting,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) {
                    if (_passwordError != null) {
                      setState(() => _passwordError = null);
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
                  label: 'Sign in',
                  isLoading: _submitting,
                  onPressed: _submitting
                      ? null
                      : () {
                          debugPrint(
                            '[auth-login-diag] LoginScreen Sign in onPressed '
                            'isLoading=$_submitting',
                          );
                          _submit();
                        },
                ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                    ),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => startNewRegisterFlow(ref, context),
                      child: Text(
                        'Sign up',
                        style: AppTextTheme.labelLarge.copyWith(color: colors.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: [
                    Expanded(child: Divider(color: colors.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: Text(
                        'or',
                        style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                      ),
                    ),
                    Expanded(child: Divider(color: colors.border)),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: 'Continue with Google',
                  variant: AppButtonVariant.secondary,
                  onPressed: _submitting ? null : () {},
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Continue with Apple',
                  variant: AppButtonVariant.secondary,
                  onPressed: _submitting ? null : () {},
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
