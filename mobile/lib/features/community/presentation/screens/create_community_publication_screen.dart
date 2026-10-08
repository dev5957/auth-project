import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../chronique/media/chronique_media_limits.dart';
import '../../../chronique/models/chronique_fields.dart';
import '../../../chronique/models/chronique_schedule_draft.dart';
import '../../../chronique/models/media_draft.dart';
import '../../../chronique/providers/chronique_providers.dart';
import '../../../chronique/presentation/widgets/add_media_kind_sheet.dart';
import '../../../chronique/presentation/widgets/audio_recording_sheet.dart';
import '../../../chronique/presentation/widgets/chronique_preview.dart';
import '../../../chronique/presentation/widgets/chronique_publication_fields.dart';
import '../../../chronique/presentation/widgets/media_draft_list.dart';
import '../state/community_feed_controller.dart';
import '../state/create_community_publication_controller.dart';

enum CreateCommunityPublicationStep { content, parameters, preview }

class CreateCommunityPublicationScreen extends ConsumerStatefulWidget {
  const CreateCommunityPublicationScreen({
    super.key,
    required this.communityId,
    this.communityName,
  });

  final int communityId;
  final String? communityName;

  @override
  ConsumerState<CreateCommunityPublicationScreen> createState() =>
      CreateCommunityPublicationScreenState();
}

class CreateCommunityPublicationScreenState
    extends ConsumerState<CreateCommunityPublicationScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _contentScrollController = ScrollController();

  String? _titleError;
  String? _bodyError;
  String? _formError;
  bool _submitting = false;
  bool _commentsEnabled = false;
  CreateCommunityPublicationStep _step = CreateCommunityPublicationStep.content;
  ChroniqueScheduleDraft _schedule = const ChroniqueScheduleDraft();

  static const double _contentScrollBottomReserve = 160;

  int get _bodyCount => ChroniqueFields.runeLength(_bodyController.text.trim());

  List<MediaDraft> get _currentMedias =>
      ref.read(createCommunityPublicationControllerProvider(widget.communityId)).medias;

  String? get _liveMediaError => chroniqueDraftMediaError(_currentMedias);

  bool get _canGoNext =>
      !_submitting &&
      ChroniqueFields.canPublishBody(_bodyController.text) &&
      _liveMediaError == null;

  bool get _canAddMedia =>
      !_submitting && _currentMedias.length < kChroniqueMaxMediaCount;

  @visibleForTesting
  ChroniqueScheduleDraft get scheduleDraft => _schedule;

  @visibleForTesting
  CreateCommunityPublicationStep get currentStep => _step;

  @visibleForTesting
  bool get commentsEnabled => _commentsEnabled;

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
    _contentScrollController.dispose();
    super.dispose();
  }

  void _discardStaleMediaFormError() {
    if (_liveMediaError == null && isChroniqueMediaFormMessage(_formError)) {
      _formError = null;
    }
  }

  void _scrollContentToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_contentScrollController.hasClients) {
        return;
      }
      _contentScrollController.jumpTo(
        _contentScrollController.position.maxScrollExtent,
      );
    });
  }

  void _onBodyEdited() {
    setState(() {
      _bodyError = ChroniqueFields.bodyError(_bodyController.text);
      _discardStaleMediaFormError();
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

  bool _validateParameters() {
    final error = _schedule.validationError();
    setState(() => _formError = error);
    return error == null;
  }

  Future<void> _addMedia() async {
    if (_submitting) {
      return;
    }
    final currentMedias =
        ref.read(createCommunityPublicationControllerProvider(widget.communityId)).medias;
    if (currentMedias.length >= kChroniqueMaxMediaCount) {
      setState(() => _formError = kTooManyMediaMessage);
      return;
    }
    final kind = await showAddMediaKindSheet(context);
    if (!mounted || kind == null) {
      return;
    }
    final controller =
        ref.read(createCommunityPublicationControllerProvider(widget.communityId).notifier);
    late final String? error;
    if (kind == MediaDraftKind.image) {
      final source = await showAddImageSourceSheet(context);
      if (!mounted || source == null) {
        return;
      }
      setState(() => _formError = null);
      error = source == MediaDraftSourceType.camera
          ? await controller.pickImageFromCamera()
          : await controller.pickImage();
    } else if (kind == MediaDraftKind.video) {
      final source = await showAddVideoSourceSheet(context);
      if (!mounted || source == null) {
        return;
      }
      setState(() => _formError = null);
      error = source == MediaDraftSourceType.camera
          ? await controller.pickVideoFromCamera()
          : await controller.pickVideo();
    } else if (kind == MediaDraftKind.audio) {
      final source = await showAddAudioSourceSheet(context);
      if (!mounted || source == null) {
        return;
      }
      setState(() => _formError = null);
      if (source == MediaDraftSourceType.microphone) {
        error = await controller.applyMediaPick(
          await showChroniqueAudioRecordingSheet(
            context,
            recorder: ref.read(chroniqueMicrophoneRecorderProvider),
          ),
        );
      } else {
        error = await controller.pickAudio();
      }
    } else {
      setState(() => _formError = null);
      error = await switch (kind) {
        MediaDraftKind.document => controller.pickDocument(),
        MediaDraftKind.image ||
        MediaDraftKind.video ||
        MediaDraftKind.audio =>
          Future<String?>.value(null),
      };
    }
    if (!mounted) {
      return;
    }
    if (error != null) {
      setState(() => _formError = error);
    }
    _scrollContentToEnd();
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
      case CreateCommunityPublicationStep.content:
        if (!_validateContent()) {
          return;
        }
        ref
            .read(createCommunityPublicationControllerProvider(widget.communityId).notifier)
            .saveDraft(
              title: ChroniqueFields.trimmedTitle(_titleController.text) ?? '',
              body: ChroniqueFields.trimmedBody(_bodyController.text),
            );
        setState(() {
          _step = CreateCommunityPublicationStep.parameters;
          _formError = null;
        });
      case CreateCommunityPublicationStep.parameters:
        if (!_validateParameters()) {
          return;
        }
        setState(() {
          _step = CreateCommunityPublicationStep.preview;
          _formError = null;
        });
      case CreateCommunityPublicationStep.preview:
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
        CreateCommunityPublicationStep.preview => CreateCommunityPublicationStep.parameters,
        CreateCommunityPublicationStep.parameters => CreateCommunityPublicationStep.content,
        CreateCommunityPublicationStep.content => CreateCommunityPublicationStep.content,
      };
    });
  }

  Future<void> _publish() async {
    if (_submitting) {
      return;
    }
    if (!_validateContent() || !_validateParameters()) {
      return;
    }

    final title = ChroniqueFields.trimmedTitle(_titleController.text);
    final body = ChroniqueFields.trimmedBody(_bodyController.text);
    ref.read(createCommunityPublicationControllerProvider(widget.communityId).notifier).saveDraft(
          title: title ?? '',
          body: body,
        );

    setState(() {
      _submitting = true;
      _formError = null;
    });

    try {
      await ref
          .read(createCommunityPublicationControllerProvider(widget.communityId).notifier)
          .publish(
            body: body,
            title: title,
            publish: _schedule.publish,
            scheduledAt: _schedule.apiScheduledAt(),
            isTimeLimited: _schedule.apiIsTimeLimited,
            expiresAt: _schedule.apiExpiresAt(),
            commentsEnabled: _commentsEnabled,
          );
      ref
          .read(createCommunityPublicationControllerProvider(widget.communityId).notifier)
          .clearDraft();
      if (!mounted) {
        return;
      }
      await ref.read(communityFeedControllerProvider(widget.communityId).notifier).load();
      if (!mounted) {
        return;
      }
      context.pop();
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
        CreateCommunityPublicationStep.content => 'Contenu',
        CreateCommunityPublicationStep.parameters => 'Paramètres',
        CreateCommunityPublicationStep.preview => 'Aperçu',
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final medias = ref.watch(
      createCommunityPublicationControllerProvider(widget.communityId).select((d) => d.medias),
    );
    return Scaffold(
      backgroundColor: colors.bgBase,
      resizeToAvoidBottomInset: true,
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
                controller: _step == CreateCommunityPublicationStep.content
                    ? _contentScrollController
                    : null,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xxl,
                  0,
                  AppSpacing.xxl,
                  _step == CreateCommunityPublicationStep.content
                      ? _contentScrollBottomReserve
                      : AppSpacing.xxl,
                ),
                child: switch (_step) {
                  CreateCommunityPublicationStep.content => _contentStep(colors, medias),
                  CreateCommunityPublicationStep.parameters => _parametersStep(),
                  CreateCommunityPublicationStep.preview => ChroniquePreview(
                      title: _titleController.text,
                      body: ChroniqueFields.trimmedBody(_bodyController.text),
                      medias: medias,
                      schedule: _schedule,
                    ),
                },
              ),
            ),
            ColoredBox(
              color: colors.bgBase,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxl,
                  AppSpacing.md,
                  AppSpacing.xxl,
                  AppSpacing.lg,
                ),
                child: _footer(),
              ),
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
          'Nouvelle publication',
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
        Text(
          'Commentaires',
          key: const ValueKey('community-assistant-comments'),
          style: AppTextTheme.titleSmall.copyWith(color: colors.textSecondary),
        ),
        ListTile(
          key: const ValueKey('community-comments-yes'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            _commentsEnabled ? Icons.radio_button_checked : Icons.radio_button_off,
            color: colors.primary,
          ),
          title: Text(
            'Oui',
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
          ),
          onTap: _submitting ? null : () => setState(() => _commentsEnabled = true),
        ),
        ListTile(
          key: const ValueKey('community-comments-no'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            !_commentsEnabled ? Icons.radio_button_checked : Icons.radio_button_off,
            color: colors.primary,
          ),
          title: Text(
            'Non',
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
          ),
          onTap: _submitting ? null : () => setState(() => _commentsEnabled = false),
        ),
        const SizedBox(height: AppSpacing.xxl),
        AppButton(
          label: '+ Ajouter un média',
          variant: AppButtonVariant.secondary,
          onPressed: _submitting ? null : _addMedia,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Médias : ${medias.length} / $kChroniqueMaxMediaCount',
          key: const ValueKey('media-count-label'),
          textAlign: TextAlign.center,
          style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
        ),
        if (medias.length >= kChroniqueMaxMediaCount) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            kMediaLimitReachedMessage,
            key: const ValueKey('media-limit-reached'),
            textAlign: TextAlign.center,
            style: AppTextTheme.labelSmall.copyWith(color: colors.danger),
          ),
        ],
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
            onRemove: _submitting
                ? null
                : (id) {
                    ref
                        .read(
                          createCommunityPublicationControllerProvider(widget.communityId)
                              .notifier,
                        )
                        .removeMediaDraft(id);
                    setState(_discardStaleMediaFormError);
                    _scrollContentToEnd();
                  },
          ),
        if (_contentBannerError(medias) != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _contentBannerError(medias)!,
            key: const ValueKey('content-media-error'),
            textAlign: TextAlign.center,
            style: AppTextTheme.labelSmall.copyWith(color: colors.danger),
          ),
        ],
        const SizedBox(
          key: ValueKey('content-media-footer-gap'),
          height: _contentScrollBottomReserve,
        ),
      ],
    );
  }

  String? _contentBannerError(List<MediaDraft> medias) {
    return chroniqueDraftMediaError(medias) ?? _formError;
  }

  Widget _parametersStep() {
    final colors = context.luminaColors;
    final name = widget.communityName?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        if (name != null && name.isNotEmpty) ...[
          Text(
            'Communauté',
            style: AppTextTheme.titleSmall.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            name,
            key: const ValueKey('community-assistant-context-name'),
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
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
        if (_step == CreateCommunityPublicationStep.preview && _formError != null) ...[
          Text(
            _formError!,
            textAlign: TextAlign.center,
            style: AppTextTheme.labelSmall.copyWith(color: colors.danger),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_step == CreateCommunityPublicationStep.content)
          Row(
            children: [
              Expanded(
                child: AppButton(
                  key: const ValueKey('wizard-add-media'),
                  label: '+ Média',
                  variant: AppButtonVariant.secondary,
                  onPressed: _canAddMedia ? _addMedia : null,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(
                  key: const ValueKey('wizard-next'),
                  label: 'Suivant',
                  onPressed: _canGoNext ? _goNext : null,
                ),
              ),
            ],
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
                child: _step == CreateCommunityPublicationStep.parameters
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
