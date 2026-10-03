import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../chronique/models/chronique_fields.dart';
import '../../models/community_publication.dart';
import '../../providers/community_providers.dart';

class EditCommunityPublicationScreen extends ConsumerStatefulWidget {
  const EditCommunityPublicationScreen({
    super.key,
    required this.publication,
  });

  final CommunityPublication publication;

  @override
  ConsumerState<EditCommunityPublicationScreen> createState() =>
      _EditCommunityPublicationScreenState();
}

class _EditCommunityPublicationScreenState
    extends ConsumerState<EditCommunityPublicationScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  String? _titleError;
  String? _bodyError;
  String? _formError;
  bool _submitting = false;

  String? get _originalTitle => ChroniqueFields.trimmedTitle(widget.publication.title ?? '');

  String get _originalBody => ChroniqueFields.trimmedBody(widget.publication.body);

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
    _titleController = TextEditingController(text: widget.publication.title ?? '');
    _bodyController = TextEditingController(text: widget.publication.body);
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

  Future<void> _save() async {
    if (!_canSave) {
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
    });
    try {
      final updated = await ref.read(communityRepositoryProvider).patchPublication(
            communityId: widget.publication.communityId,
            publicationId: widget.publication.id,
            title: ChroniqueFields.trimmedTitle(_titleController.text),
            body: ChroniqueFields.trimmedBody(_bodyController.text),
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
        _formError = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final count = ChroniqueFields.runeLength(_bodyController.text.trim());
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text('Modifier la publication'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    AppTextField(
                      label: 'Titre (optionnel)',
                      hint: 'Titre',
                      controller: _titleController,
                      errorText: _titleError,
                      enabled: !_submitting,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppTextField(
                      label: 'Texte *',
                      hint: 'Votre texte',
                      controller: _bodyController,
                      errorText: _bodyError,
                      enabled: !_submitting,
                      minLines: 6,
                      maxLines: 12,
                      keyboardType: TextInputType.multiline,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '$count / ${ChroniqueFields.bodyMax}',
                      textAlign: TextAlign.right,
                      style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                AppSpacing.md,
                AppSpacing.xxl,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_formError != null) ...[
                    Text(
                      _formError!,
                      textAlign: TextAlign.center,
                      style: AppTextTheme.labelSmall.copyWith(color: colors.danger),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  AppButton(
                    key: const ValueKey('community-publication-save'),
                    label: 'Enregistrer',
                    isLoading: _submitting,
                    onPressed: _canSave ? _save : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
