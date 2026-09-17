import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../providers/auth_controller.dart';
import '../state/register_flow_controller.dart';
import '../state/register_form_data.dart';
import '../state/register_phone.dart';

/// Étape 3 — Phone. Premier appel `startRegister()` via [AuthController].
class RegisterPhoneStep extends ConsumerStatefulWidget {
  const RegisterPhoneStep({
    super.key,
    required this.onCodeSent,
  });

  final VoidCallback onCodeSent;

  @override
  ConsumerState<RegisterPhoneStep> createState() => _RegisterPhoneStepState();
}

class _RegisterPhoneStepState extends ConsumerState<RegisterPhoneStep> {
  late final TextEditingController _phoneController;
  bool _submitting = false;
  String? _formError;
  String? _phoneApiError;

  @override
  void initState() {
    super.initState();
    final data = ref.read(registerFlowProvider).data;
    _phoneController = TextEditingController(text: data.phoneNumber ?? '');
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String? get _phoneError => validateRegisterPhoneNumber(_phoneController.text);

  bool get _canSend => !_submitting && _phoneError == null;

  void _persist({String? phoneNumber}) {
    ref.read(registerFlowProvider.notifier).savePhone(
          phoneNumber: phoneNumber ??
              (_phoneController.text.trim().isEmpty
                  ? null
                  : _phoneController.text),
        );
  }

  void _onChanged() {
    _persist();
    setState(() {
      _formError = null;
      _phoneApiError = null;
    });
  }

  String _messageFor(ApiException error) {
    final message = error.message.trim();
    if (message.isNotEmpty) {
      return message;
    }
    switch (error.statusCode) {
      case 400:
        return 'Invalid registration data';
      case 409:
        return 'Email, login or phone number is already in use';
      case 429:
        return 'Too many requests';
      case 503:
        return 'SMS could not be sent';
      default:
        return 'Unexpected error';
    }
  }

  bool _isPhoneFieldError(String message) {
    return message == 'phone_number is required' ||
        message == 'phone_number is invalid';
  }

  Future<void> _sendCode() async {
    if (!_canSend) {
      return;
    }
    final phoneError = _phoneError;
    if (phoneError != null) {
      setState(() {});
      return;
    }

    final normalized = normalizeRegisterPhoneNumber(_phoneController.text);
    _persist(phoneNumber: normalized);

    final data = ref.read(registerFlowProvider).data;
    final birthDate = data.formattedBirthDate;
    final login = data.login?.trim();
    final email = data.email?.trim();
    final password = data.password;
    final passwordConfirmation = data.confirmPassword ?? password;
    if (birthDate == null ||
        login == null ||
        login.isEmpty ||
        email == null ||
        email.isEmpty ||
        password == null ||
        password.isEmpty ||
        passwordConfirmation == null ||
        passwordConfirmation.isEmpty) {
      setState(() => _formError = 'Registration data is incomplete');
      return;
    }

    setState(() {
      _submitting = true;
      _formError = null;
      _phoneApiError = null;
    });

    try {
      final result = await ref.read(authControllerProvider.notifier).startRegister(
            email: email,
            login: login,
            phoneNumber: normalized,
            birthDate: birthDate,
            password: password,
            passwordConfirmation: passwordConfirmation,
            firstName: data.firstName,
            lastName: data.lastName,
          );
      if (!mounted) {
        return;
      }
      final flow = ref.read(registerFlowProvider.notifier);
      if (ref.read(registerFlowProvider).step != RegisterStep.phone) {
        return;
      }
      flow.savePhone(phoneNumber: normalized);
      flow.saveVerificationToken(result.verificationToken);
      widget.onCodeSent();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      final message = _messageFor(error);
      setState(() {
        _submitting = false;
        if (_isPhoneFieldError(message)) {
          _phoneApiError = message;
          _formError = null;
        } else {
          _phoneApiError = null;
          _formError = message;
        }
      });
    } on FormatException {
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
    final phoneError = _phoneApiError ??
        (_phoneController.text.isEmpty ? null : _phoneError);

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
          'Step 3 of 4 · Phone',
          textAlign: TextAlign.center,
          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'We will send a verification code to this number. Standard SMS rates may apply.',
          textAlign: TextAlign.center,
          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        AppTextField(
          label: 'Phone number *',
          hint: '+15551234567',
          controller: _phoneController,
          errorText: phoneError,
          enabled: !_submitting,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.telephoneNumber],
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => _sendCode(),
          onChanged: (_) => _onChanged(),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '* Required',
          style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
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
          label: 'Send code',
          isLoading: _submitting,
          onPressed: _canSend ? _sendCode : null,
        ),
      ],
    );
  }
}
