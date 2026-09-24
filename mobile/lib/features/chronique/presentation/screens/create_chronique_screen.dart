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
import '../../models/chronique_fields.dart';
import '../state/create_chronique_controller.dart';
import '../widgets/add_media_kind_sheet.dart';
import '../widgets/media_draft_list.dart';

/// Assistant de création V1 (modal plein écran). Texte uniquement.
class CreateChroniqueScreen extends ConsumerStatefulWidget {
  const CreateChroniqueScreen({super.key});

  @override
  ConsumerState<CreateChroniqueScreen> createState() => _CreateChroniqueScreenState();
}

class _CreateChroniqueScreenState extends ConsumerState<CreateChroniqueScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String? _titleError;
  String? _bodyError;
  String? _formError;
  bool _submitting = false;

  int get _bodyCount => ChroniqueFields.runeLength(_bodyController.text.trim());

  bool get _canPublish =>
      !_submitting && ChroniqueFields.canPublishBody(_bodyController.text);

  @override
  void initState() {
    super.initState();
    _bodyController.addListener(_onBodyEdited);
    _titleController.addListener(_onTitleEdited);
  }

  @override
  void dispose() {
    _bodyController.removeListener(_onBodyEdited);
    _titleController.removeListener(_onTitleEdited);
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onBodyEdited() {
    setState(() {
      _bodyError = ChroniqueFields.bodyError(_bodyController.text);
    });
  }

  void _onTitleEdited() {
    setState(() {
      _titleError = ChroniqueFields.titleError(_titleController.text);
    });
  }

  bool _validate() {
    final bodyError = ChroniqueFields.bodyError(_bodyController.text);
    final titleError = ChroniqueFields.titleError(_titleController.text);
    setState(() {
      _bodyError = bodyError;
      _titleError = titleError;
      _formError = null;
    });
    return bodyError == null && titleError == null;
  }

  Future<void> _addMedia() async {
    if (_submitting) {
      return;
    }
    final kind = await showAddMediaKindSheet(context);
    if (!mounted || kind == null) {
      return;
    }
    ref.read(createChroniqueControllerProvider.notifier).addMediaDraft(kind: kind);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fonction disponible prochainement')),
    );
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

    final title = ChroniqueFields.trimmedTitle(_titleController.text);
    final body = ChroniqueFields.trimmedBody(_bodyController.text);
    ref.read(createChroniqueControllerProvider.notifier).saveDraft(
          title: title ?? '',
          body: body,
        );

    setState(() {
      _submitting = true;
      _formError = null;
    });

    try {
      await ref.read(createChroniqueControllerProvider.notifier).publish(
            body: body,
            title: title,
          );
      ref.read(createChroniqueControllerProvider.notifier).clearDraft();
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
    final medias = ref.watch(createChroniqueControllerProvider.select((d) => d.medias));
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
                errorText: _titleError,
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
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '$_bodyCount / ${ChroniqueFields.bodyMax}',
                textAlign: TextAlign.right,
                style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppButton(
                label: '+ Ajouter un média',
                variant: AppButtonVariant.secondary,
                onPressed: _submitting ? null : _addMedia,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (medias.isEmpty)
                Text(
                  'Aucun média ajouté',
                  textAlign: TextAlign.center,
                  style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                )
              else
                MediaDraftList(
                  medias: medias,
                  onRemove: (id) {
                    ref.read(createChroniqueControllerProvider.notifier).removeMediaDraft(id);
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
                onPressed: _canPublish ? _publish : null,
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
