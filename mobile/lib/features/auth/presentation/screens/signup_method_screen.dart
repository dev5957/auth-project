import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_logo.dart';
import '../continue_with_google.dart';
import '../state/register_flow_controller.dart';

/// Choix du mode d’inscription. Uniquement après Get Started, pas le Login.
class SignupMethodScreen extends ConsumerStatefulWidget {
  const SignupMethodScreen({super.key});

  @override
  ConsumerState<SignupMethodScreen> createState() => _SignupMethodScreenState();
}

class _SignupMethodScreenState extends ConsumerState<SignupMethodScreen> {
  bool _googleSigningIn = false;
  String? _formError;

  Future<void> _continueWithGoogle() async {
    if (_googleSigningIn) {
      return;
    }
    setState(() {
      _googleSigningIn = true;
      _formError = null;
    });
    try {
      await continueWithGoogleFromUi(
        ref: ref,
        context: context,
        onLocalError: (message) {
          setState(() => _formError = message);
        },
      );
    } finally {
      if (mounted) {
        setState(() => _googleSigningIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        foregroundColor: colors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AppLogo(size: 72)),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'Create your account',
                textAlign: TextAlign.center,
                style: AppTextTheme.titleLarge.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Choose how to create your account',
                textAlign: TextAlign.center,
                style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Google and Apple replace login and password. Email uses the classic Sign Up.',
                textAlign: TextAlign.center,
                style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
              ),
              if (_formError != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _formError!,
                  textAlign: TextAlign.center,
                  style: AppTextTheme.labelSmall.copyWith(color: colors.danger),
                ),
              ],
              const SizedBox(height: AppSpacing.xxxl),
              AppButton(
                label: 'Continue with email / password',
                onPressed: _googleSigningIn
                    ? null
                    : () => startNewRegisterFlow(ref, context),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Continue with Google',
                variant: AppButtonVariant.secondary,
                isLoading: _googleSigningIn,
                onPressed: _googleSigningIn ? null : _continueWithGoogle,
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Continue with Apple',
                variant: AppButtonVariant.secondary,
                onPressed: _googleSigningIn ? null : () {},
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
