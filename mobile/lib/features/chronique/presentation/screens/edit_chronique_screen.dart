import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../models/chronique.dart';
import '../../models/chronique_fields.dart';
import '../../models/media_draft.dart';
import '../state/edit_chronique_controller.dart';
import '../widgets/media_draft_list.dart';

/// Édition V1 d’une chronique publiée (texte uniquement).
class EditChroniqueScreen extends ConsumerStatefulWidget {
  const EditChroniqueScreen({
    super.key,
    required this.chronique,
  });

  final Chronique chronique;

  @override
  ConsumerState<EditChroniqueScreen> createState() => _EditChroniqueScreenState();
}

class _EditChroniqueScreenState extends ConsumerState<EditChroniqueScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;

  String? _titleError;
  String? _bodyError;
  String? _formError;
  bool _submitting = false;

  String? get _originalTitle => ChroniqueFields.trimmedTitle(widget.chronique.title ?? '');

  String get _originalBody => ChroniqueFields.trimmedBody(widget.chronique.body);

  int get _bodyCount => ChroniqueFields.runeLength(_bodyController.text.trim());

  bool get _isDirty {
    final title = ChroniqueFields.trimmedTitle(_titleController.text);
    final body = ChroniqueFields.trimmedBody(_bodyController.text);
    return title != _originalTitle || body != _originalBody;
  }

  bool get _canSave =>
      !_submitting &&
      _isDirty &&
      ChroniqueFields.bodyError(_bodyController.text) == null &&
      ChroniqueFields.titleError(_titleController.text) == null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.chronique.title ?? '');
    _bodyController = TextEditingController(text: widget.chronique.body);
    _bodyController.addListener(_onFieldsEdited);
    _titleController.addListener(_onFieldsEdited);
  }

  @override
  void dispose() {
    _bodyController.removeListener(_onFieldsEdited);
    _titleController.removeListener(_onFieldsEdited);
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onFieldsEdited() {
    setState(() {
      _bodyError = ChroniqueFields.bodyError(_bodyController.text);
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

  Future<void> _save() async {
    if (_submitting || !_isDirty) {
      return;
    }
    if (!_validate()) {
      return;
    }

    final title = ChroniqueFields.trimmedTitle(_titleController.text);
    final body = ChroniqueFields.trimmedBody(_bodyController.text);

    setState(() {
      _submitting = true;
      _formError = null;
    });

    try {
      final updated = await ref.read(editChroniqueControllerProvider.notifier).save(
            id: widget.chronique.id,
            body: body,
            title: title,
          );
      if (!mounted) {
        return;
      }
      context.pop(updated);
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
          'Modifier la chronique',
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
                'Édition',
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
              if (widget.chronique.media.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  'Médias',
                  style: AppTextTheme.titleSmall.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final media in widget.chronique.media) ...[
                  _ReadOnlyMediaRow(media: media),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
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
                label: 'Enregistrer',
                isLoading: _submitting,
                onPressed: _canSave ? _save : null,
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyMediaRow extends StatelessWidget {
  const _ReadOnlyMediaRow({required this.media});

  final ChroniqueMedia media;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final kind = switch (media.kind) {
      'image' => MediaDraftKind.image,
      'video' => MediaDraftKind.video,
      'audio' => MediaDraftKind.audio,
      'document' => MediaDraftKind.document,
      _ => null,
    };
    final name = media.originalFilename?.trim();
    final size = mediaDraftSizeLabel(media.byteSize);
    return Row(
      children: [
        Icon(
          kind == null ? Icons.attach_file : mediaDraftKindIcon(kind),
          color: colors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (name == null || name.isEmpty) ? media.kind : name,
                style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
              ),
              if (size != null)
                Text(
                  size,
                  style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
