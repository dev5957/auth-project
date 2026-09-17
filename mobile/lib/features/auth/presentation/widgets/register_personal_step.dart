import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../state/register_flow_controller.dart';

/// Étape 1 — Personal. Les étapes suivantes seront branchées plus tard.
class RegisterPersonalStep extends ConsumerStatefulWidget {
  const RegisterPersonalStep({
    super.key,
    required this.onContinue,
  });

  final VoidCallback onContinue;

  @override
  ConsumerState<RegisterPersonalStep> createState() => _RegisterPersonalStepState();
}

class _RegisterPersonalStepState extends ConsumerState<RegisterPersonalStep> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _birthDateController;
  String? _birthDateError;

  @override
  void initState() {
    super.initState();
    final data = ref.read(registerFlowProvider).data;
    _firstNameController = TextEditingController(text: data.firstName ?? '');
    _lastNameController = TextEditingController(text: data.lastName ?? '');
    _birthDateController = TextEditingController(text: _formatDate(data.birthDate));
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return '';
    }
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String? _optionalName(String raw) {
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _pickBirthDate() async {
    final colors = context.luminaColors;
    final current = ref.read(registerFlowProvider).data.birthDate;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: colors.primary,
                  onPrimary: colors.textOnPrimary,
                  surface: colors.bgSurface,
                  onSurface: colors.textPrimary,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) {
      return;
    }
    ref.read(registerFlowProvider.notifier).savePersonal(
          firstName: _optionalName(_firstNameController.text),
          lastName: _optionalName(_lastNameController.text),
          birthDate: picked,
        );
    setState(() {
      _birthDateController.text = _formatDate(picked);
      _birthDateError = null;
    });
  }

  bool _validateBirthDate(DateTime? date) {
    if (date == null) {
      setState(() => _birthDateError = 'Date of birth is required');
      return false;
    }
    final today = DateTime.now();
    final endOfToday = DateTime(today.year, today.month, today.day);
    if (date.isAfter(endOfToday)) {
      setState(() => _birthDateError = 'Date of birth cannot be in the future');
      return false;
    }
    setState(() => _birthDateError = null);
    return true;
  }

  void _onContinue() {
    final birthDate = ref.read(registerFlowProvider).data.birthDate;
    if (!_validateBirthDate(birthDate)) {
      return;
    }
    ref.read(registerFlowProvider.notifier).savePersonal(
          firstName: _optionalName(_firstNameController.text),
          lastName: _optionalName(_lastNameController.text),
          birthDate: birthDate!,
        );
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Create your account',
          textAlign: TextAlign.center,
          style: AppTextTheme.titleLarge.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Step 1 of 4 · Personal',
          textAlign: TextAlign.center,
          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        AppTextField(
          label: 'First name (optional)',
          hint: 'First name',
          controller: _firstNameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.givenName],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Last name (optional)',
          hint: 'Last name',
          controller: _lastNameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.familyName],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Date of birth *',
          hint: 'YYYY-MM-DD',
          controller: _birthDateController,
          errorText: _birthDateError,
          readOnly: true,
          onTap: _pickBirthDate,
          keyboardType: TextInputType.datetime,
          textInputAction: TextInputAction.done,
          suffixIcon: IconButton(
            onPressed: _pickBirthDate,
            tooltip: 'Choose date',
            icon: Icon(
              Icons.calendar_today_outlined,
              color: colors.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '* Required',
          style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        AppButton(
          label: 'Continue',
          onPressed: _onContinue,
        ),
      ],
    );
  }
}
