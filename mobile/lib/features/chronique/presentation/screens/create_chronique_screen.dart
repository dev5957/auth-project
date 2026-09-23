import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../state/create_chronique_controller.dart';

/// Assistant de création V1 (modal plein écran). Texte uniquement.
class CreateChroniqueScreen extends ConsumerStatefulWidget {
  const CreateChroniqueScreen({super.key});

  @override
  ConsumerState<CreateChroniqueScreen> createState() => _CreateChroniqueScreenState();
}

class _CreateChroniqueScreenState extends ConsumerState<CreateChroniqueScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String? _bodyError;
  String? _formError;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  bool _validate() {
    final body = _bodyController.text.trim();
    final bodyError = body.isEmpty ? 'Le texte est obligatoire' : null;
    setState(() {
      _bodyError = bodyError;
      _formError = null;
    });
    return bodyError == null;
  }

  String _messageFor(ApiException error) {
    final message = error.message.trim();
    if (message.isNotEmpty) {
      return message;
    }
    switch (error.statusCode) {
      case 401:
        return 'Unauthorized';
      case 429:
        return 'Too many requests';
      default:
        return 'Unexpected error';
    }
  }

  Future<void> _publish() async {
    if (_submitting) {
      return;
    }
    if (!_validate()) {
      return;
    }

    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    ref.read(createChroniqueControllerProvider.notifier).saveDraft(
          title: title,
          body: body,
        );

    setState(() {
      _submitting = true;
      _formError = null;
    });

    try {
      await ref.read(createChroniqueControllerProvider.notifier).publish(
            body: body,
            title: title.isEmpty ? null : title,
          );
      if (!mounted) {
        return;
      }
      context.pushReplacement(AppRoutes.explore);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _formError = _messageFor(error);
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
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        title: Text(
          'Créer une chronique',
          style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Nouvelle chronique',
                style: AppTextTheme.titleSmall.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppTextField(
                label: 'Titre (optionnel)',
                hint: 'Titre',
                controller: _titleController,
                enabled: !_submitting,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: 'Texte *',
                hint: 'Votre texte',
                controller: _bodyController,
                errorText: _bodyError,
                enabled: !_submitting,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                textCapitalization: TextCapitalization.sentences,
                minLines: 6,
                maxLines: 12,
                onChanged: (_) {
                  if (_bodyError != null) {
                    setState(() => _bodyError = null);
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
                label: 'Publier',
                isLoading: _submitting,
                onPressed: _submitting ? null : _publish,
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
