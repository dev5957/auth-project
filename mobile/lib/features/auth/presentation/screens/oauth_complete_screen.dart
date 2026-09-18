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
import '../../../../core/widgets/app_text_field.dart';
import '../../providers/auth_controller.dart';
import '../state/oauth_complete_flow_controller.dart';
import '../state/register_phone.dart';

/// Complétion profil Google. Pas le Sign Up local, pas de mot de passe.
class OAuthCompleteScreen extends ConsumerWidget {
  const OAuthCompleteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final step = ref.watch(oauthCompleteFlowProvider.select((state) => state.step));
    final email = ref.watch(oauthCompleteFlowProvider.select((state) => state.email));

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            final current = ref.read(oauthCompleteFlowProvider).step;
            if (current == OAuthCompleteStep.phone) {
              context.pop();
              return;
            }
            ref.read(oauthCompleteFlowProvider.notifier).goToPreviousStep();
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
                'Complete your profile',
                textAlign: TextAlign.center,
                style: AppTextTheme.titleLarge.copyWith(color: colors.textPrimary),
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  email,
                  textAlign: TextAlign.center,
                  style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              switch (step) {
                OAuthCompleteStep.phone => const _OAuthPhoneStep(),
                OAuthCompleteStep.otp => const _OAuthOtpStep(),
                OAuthCompleteStep.birthDate => const _OAuthBirthDateStep(),
                OAuthCompleteStep.publicLogin => const _OAuthPublicLoginStep(),
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
  switch (error.statusCode) {
    case 400:
      return 'Invalid verification code';
    case 409:
      return 'Email, login or phone number is already in use';
    case 429:
      return 'Too many requests';
    default:
      return 'Unexpected error';
  }
}

class _OAuthPhoneStep extends ConsumerStatefulWidget {
  const _OAuthPhoneStep();

  @override
  ConsumerState<_OAuthPhoneStep> createState() => _OAuthPhoneStepState();
}

class _OAuthPhoneStepState extends ConsumerState<_OAuthPhoneStep> {
  late final TextEditingController _phoneController;
  bool _submitting = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(
      text: ref.read(oauthCompleteFlowProvider).phoneNumber ?? '',
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final error = validateRegisterPhoneNumber(_phoneController.text);
    if (error != null) {
      setState(() => _formError = error);
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
    });
    final phone = normalizeRegisterPhoneNumber(_phoneController.text);
    final token = ref.read(oauthCompleteFlowProvider).oauthVerificationToken;
    try {
      final next = await ref.read(authControllerProvider.notifier).startOAuthPhone(
            oauthVerificationToken: token,
            phoneNumber: phone,
          );
      if (!mounted) {
        return;
      }
      ref.read(oauthCompleteFlowProvider.notifier)
        ..replaceOauthVerificationToken(next)
        ..savePhone(phone);
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
          'Your phone number',
          style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'We will send a verification code. Google does not replace this step.',
          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Phone number',
          hint: '+33612345678',
          controller: _phoneController,
          keyboardType: TextInputType.phone,
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
          label: 'Send code',
          isLoading: _submitting,
          onPressed: _submitting ? null : _sendCode,
        ),
      ],
    );
  }
}

class _OAuthOtpStep extends ConsumerStatefulWidget {
  const _OAuthOtpStep();

  @override
  ConsumerState<_OAuthOtpStep> createState() => _OAuthOtpStepState();
}

class _OAuthOtpStepState extends ConsumerState<_OAuthOtpStep> {
  late final TextEditingController _codeController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(
      text: ref.read(oauthCompleteFlowProvider).otpCode ?? '',
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
    ref.read(oauthCompleteFlowProvider.notifier).saveOtp(code);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the code',
          style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'SMS code',
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

class _OAuthBirthDateStep extends ConsumerStatefulWidget {
  const _OAuthBirthDateStep();

  @override
  ConsumerState<_OAuthBirthDateStep> createState() => _OAuthBirthDateStepState();
}

class _OAuthBirthDateStepState extends ConsumerState<_OAuthBirthDateStep> {
  late final TextEditingController _birthController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _birthController = TextEditingController(
      text: ref.read(oauthCompleteFlowProvider).birthDate ?? '',
    );
  }

  @override
  void dispose() {
    _birthController.dispose();
    super.dispose();
  }

  void _continue() {
    final value = _birthController.text.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      setState(() => _error = 'Use YYYY-MM-DD');
      return;
    }
    ref.read(oauthCompleteFlowProvider.notifier).saveBirthDate(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Date of birth',
          style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Required by the app. Google does not provide this.',
          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Date of birth',
          hint: '2000-01-15',
          controller: _birthController,
          keyboardType: TextInputType.datetime,
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

class _OAuthPublicLoginStep extends ConsumerStatefulWidget {
  const _OAuthPublicLoginStep();

  @override
  ConsumerState<_OAuthPublicLoginStep> createState() => _OAuthPublicLoginStepState();
}

class _OAuthPublicLoginStepState extends ConsumerState<_OAuthPublicLoginStep> {
  late final TextEditingController _loginController;
  bool _submitting = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _loginController = TextEditingController(
      text: ref.read(oauthCompleteFlowProvider).publicLogin ?? '',
    );
  }

  @override
  void dispose() {
    _loginController.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    final login = _loginController.text.trim();
    if (login.isEmpty) {
      setState(() => _formError = 'Public login is required');
      return;
    }
    if (login.length > 64) {
      setState(() => _formError = 'login is invalid');
      return;
    }
    final flow = ref.read(oauthCompleteFlowProvider);
    final code = flow.otpCode;
    final birthDate = flow.birthDate;
    if (code == null || birthDate == null) {
      setState(() => _formError = 'Complete the previous steps');
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).continueOAuthProfile(
            oauthVerificationToken: flow.oauthVerificationToken,
            code: code,
            birthDate: birthDate,
            login: login,
          );
      if (!mounted) {
        return;
      }
      context.go(AppRoutes.home);
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
          'Public login',
          style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'This is how you appear in the app. It is not a password and you will not use it to sign in.',
          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Public login',
          hint: 'Your public username',
          controller: _loginController,
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
          label: 'Create account',
          isLoading: _submitting,
          onPressed: _submitting ? null : _createAccount,
        ),
      ],
    );
  }
}
