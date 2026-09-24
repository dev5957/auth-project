import 'package:flutter/foundation.dart';
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
import '../../models/chronique_schedule_draft.dart';
import '../../models/media_draft.dart';
import '../state/create_chronique_controller.dart';
import '../widgets/add_media_kind_sheet.dart';
import '../widgets/chronique_preview.dart';
import '../widgets/chronique_publication_fields.dart';
import '../widgets/media_draft_list.dart';

enum CreateChroniqueStep { content, publication, preview }

/// Assistant de création V1 en 3 étapes (modal plein écran).
class CreateChroniqueScreen extends ConsumerStatefulWidget {
  const CreateChroniqueScreen({super.key});

  @override
  ConsumerState<CreateChroniqueScreen> createState() => CreateChroniqueScreenState();
}

class CreateChroniqueScreenState extends ConsumerState<CreateChroniqueScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String? _titleError;
  String? _bodyError;
  String? _formError;
  bool _submitting = false;
  CreateChroniqueStep _step = CreateChroniqueStep.content;
  ChroniqueScheduleDraft _schedule = const ChroniqueScheduleDraft();

  int get _bodyCount => ChroniqueFields.runeLength(_bodyController.text.trim());

  bool get _canGoNext =>
      !_submitting && ChroniqueFields.canPublishBody(_bodyController.text);

  @visibleForTesting
  ChroniqueScheduleDraft get scheduleDraft => _schedule;

  @visibleForTesting
  CreateChroniqueStep get currentStep => _step;

  @visibleForTesting
  void debugSetScheduleDraft(ChroniqueScheduleDraft draft) {
    setState(() => _schedule = draft);
  }

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

  bool _validateContent() {
    final bodyError = ChroniqueFields.bodyError(_bodyController.text);
    final titleError = ChroniqueFields.titleError(_titleController.text);
    setState(() {
      _bodyError = bodyError;
      _titleError = titleError;
      _formError = null;
    });
    return bodyError == null && titleError == null;
  }

  bool _validatePublication() {
    final error = _schedule.validationError();
    setState(() => _formError = error);
    return error == null;
  }

  Future<void> _addMedia() async {
    if (_submitting) {
      return;
    }
    final kind = await showAddMediaKindSheet(context);
    if (!mounted || kind == null) {
      return;
    }
    setState(() => _formError = null);
    final controller = ref.read(createChroniqueControllerProvider.notifier);
    final error = await switch (kind) {
      MediaDraftKind.image => controller.pickImage(),
      MediaDraftKind.video => controller.pickVideo(),
      MediaDraftKind.audio => controller.pickAudio(),
      MediaDraftKind.document => controller.pickDocument(),
    };
    if (!mounted || error == null) {
      return;
    }
    setState(() => _formError = error);
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

  void _goNext() {
    if (_submitting) {
      return;
    }
    switch (_step) {
      case CreateChroniqueStep.content:
        if (!_validateContent()) {
          return;
        }
        ref.read(createChroniqueControllerProvider.notifier).saveDraft(
              title: ChroniqueFields.trimmedTitle(_titleController.text) ?? '',
              body: ChroniqueFields.trimmedBody(_bodyController.text),
            );
        setState(() {
          _step = CreateChroniqueStep.publication;
          _formError = null;
        });
      case CreateChroniqueStep.publication:
        if (!_validatePublication()) {
          return;
        }
        setState(() {
          _step = CreateChroniqueStep.preview;
          _formError = null;
        });
      case CreateChroniqueStep.preview:
        break;
    }
  }

  void _goBack() {
    if (_submitting) {
      return;
    }
    setState(() {
      _formError = null;
      _step = switch (_step) {
        CreateChroniqueStep.preview => CreateChroniqueStep.publication,
        CreateChroniqueStep.publication => CreateChroniqueStep.content,
        CreateChroniqueStep.content => CreateChroniqueStep.content,
      };
    });
  }

  Future<void> _publish() async {
    if (_submitting) {
      return;
    }
    if (!_validateContent() || !_validatePublication()) {
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
            publish: _schedule.publish,
            scheduledAt: _schedule.apiScheduledAt(),
            isTimeLimited: _schedule.apiIsTimeLimited,
            expiresAt: _schedule.apiExpiresAt(),
          );
      ref.read(createChroniqueControllerProvider.notifier).clearDraft();
      if (!mounted) {
        return;
      }
      final destination = _schedule.publishMode == ChroniquePublishMode.schedule
          ? AppRoutes.upcoming
          : AppRoutes.explore;
      context.pushReplacement(destination);
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

  String get _stepTitle => switch (_step) {
        CreateChroniqueStep.content => 'Contenu',
        CreateChroniqueStep.publication => 'Publication',
        CreateChroniqueStep.preview => 'Aperçu',
      };

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
          _stepTitle,
          style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                child: switch (_step) {
                  CreateChroniqueStep.content => _contentStep(colors, medias),
                  CreateChroniqueStep.publication => _publicationStep(),
                  CreateChroniqueStep.preview => ChroniquePreview(
                      title: _titleController.text,
                      body: ChroniqueFields.trimmedBody(_bodyController.text),
                      medias: medias,
                      schedule: _schedule,
                    ),
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                AppSpacing.md,
                AppSpacing.xxl,
                AppSpacing.lg,
              ),
              child: _footer(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contentStep(LuminaColors colors, List<MediaDraft> medias) {
    return Column(
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
      ],
    );
  }

  Widget _publicationStep() {
    final colors = context.luminaColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        ChroniquePublicationFields(
          draft: _schedule,
          enabled: !_submitting,
          onChanged: (draft) => setState(() {
            _schedule = draft;
            _formError = null;
          }),
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
      ],
    );
  }

  Widget _footer() {
    final colors = context.luminaColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_step == CreateChroniqueStep.preview && _formError != null) ...[
          Text(
            _formError!,
            textAlign: TextAlign.center,
            style: AppTextTheme.labelSmall.copyWith(color: colors.danger),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_step == CreateChroniqueStep.content)
          AppButton(
            key: const ValueKey('wizard-next'),
            label: 'Suivant',
            onPressed: _canGoNext ? _goNext : null,
          )
        else
          Row(
            children: [
              Expanded(
                child: AppButton(
                  key: const ValueKey('wizard-back'),
                  label: 'Retour',
                  variant: AppButtonVariant.secondary,
                  onPressed: _submitting ? null : _goBack,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _step == CreateChroniqueStep.publication
                    ? AppButton(
                        key: const ValueKey('wizard-next'),
                        label: 'Suivant',
                        onPressed: _submitting ? null : _goNext,
                      )
                    : AppButton(
                        key: const ValueKey('wizard-publish'),
                        label: 'Publier',
                        isLoading: _submitting,
                        onPressed: _submitting ? null : _publish,
                      ),
              ),
            ],
          ),
      ],
    );
  }
}
