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
import '../../models/chronique_date.dart';
import '../../models/chronique_fields.dart';
import '../../models/media_draft.dart';
import '../state/create_chronique_controller.dart';
import '../widgets/add_media_kind_sheet.dart';
import '../widgets/media_draft_list.dart';

/// Assistant de création V1 (modal plein écran). Publication texte ; médias locaux.
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
  bool _schedule = false;
  DateTime? _scheduledLocal;
  ChroniqueExpirationPreset _expiration = ChroniqueExpirationPreset.none;
  DateTime? _customExpiresLocal;

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
    final temporalError = _temporalError();
    setState(() {
      _bodyError = bodyError;
      _titleError = titleError;
      _formError = temporalError;
    });
    return bodyError == null && titleError == null && temporalError == null;
  }

  DateTime get _activationLocal {
    if (_schedule) {
      return _scheduledLocal ?? ChroniqueDateHelper.defaultScheduleLocal();
    }
    return DateTime.now();
  }

  String? _temporalError() {
    if (_schedule) {
      final scheduleError = ChroniqueDateHelper.scheduleError(_scheduledLocal);
      if (scheduleError != null) {
        return scheduleError;
      }
    }
    return ChroniqueDateHelper.expirationError(
      preset: _expiration,
      activationLocal: _activationLocal,
      customLocal: _customExpiresLocal,
    );
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

    final publish = _schedule ? 'schedule' : 'now';
    final scheduledAt = _schedule && _scheduledLocal != null
        ? ChroniqueDateHelper.toUtcIso(_scheduledLocal!)
        : null;
    final expiresLocal = ChroniqueDateHelper.resolveExpirationLocal(
      preset: _expiration,
      activationLocal: _activationLocal,
      customLocal: _customExpiresLocal,
    );
    final isTimeLimited = _expiration != ChroniqueExpirationPreset.none;
    final expiresAt =
        isTimeLimited && expiresLocal != null ? ChroniqueDateHelper.toUtcIso(expiresLocal) : null;

    setState(() {
      _submitting = true;
      _formError = null;
    });

    try {
      await ref.read(createChroniqueControllerProvider.notifier).publish(
            body: body,
            title: title,
            publish: publish,
            scheduledAt: scheduledAt,
            isTimeLimited: isTimeLimited,
            expiresAt: expiresAt,
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

  Future<void> _pickScheduledDate() async {
    final initial = _scheduledLocal ?? ChroniqueDateHelper.defaultScheduleLocal();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _scheduledLocal = ChroniqueDateHelper.combineLocal(
        picked,
        TimeOfDay.fromDateTime(_scheduledLocal ?? initial),
      );
    });
  }

  Future<void> _pickScheduledTime() async {
    final initial = _scheduledLocal ?? ChroniqueDateHelper.defaultScheduleLocal();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _scheduledLocal = ChroniqueDateHelper.combineLocal(initial, picked);
    });
  }

  Future<void> _pickExpiresDate() async {
    final initial = _customExpiresLocal ?? DateTime.now().add(const Duration(hours: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _customExpiresLocal = ChroniqueDateHelper.combineLocal(
        picked,
        TimeOfDay.fromDateTime(_customExpiresLocal ?? initial),
      );
    });
  }

  Future<void> _pickExpiresTime() async {
    final initial = _customExpiresLocal ?? DateTime.now().add(const Duration(hours: 1));
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _customExpiresLocal = ChroniqueDateHelper.combineLocal(initial, picked);
    });
  }

  Widget _sectionTitle(String label, Color color) {
    return Text(
      label,
      style: AppTextTheme.titleSmall.copyWith(color: color),
    );
  }

  Widget _dateButton({
    required Key key,
    required String label,
    required String value,
    required VoidCallback? onPressed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppTextTheme.labelSmall),
        const SizedBox(height: AppSpacing.xs),
        OutlinedButton(
          key: key,
          onPressed: onPressed,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(value),
          ),
        ),
      ],
    );
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
              _sectionTitle('Publication', colors.textSecondary),
              ListTile(
                key: const ValueKey('publish-now'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _schedule ? Icons.radio_button_off : Icons.radio_button_checked,
                  color: colors.primary,
                ),
                title: Text(
                  'Maintenant',
                  style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
                ),
                onTap: _submitting
                    ? null
                    : () => setState(() => _schedule = false),
              ),
              ListTile(
                key: const ValueKey('publish-schedule'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _schedule ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: colors.primary,
                ),
                title: Text(
                  'Programmer',
                  style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
                ),
                onTap: _submitting
                    ? null
                    : () {
                        setState(() {
                          _schedule = true;
                          _scheduledLocal ??= ChroniqueDateHelper.defaultScheduleLocal();
                        });
                      },
              ),
              if (_schedule) ...[
                _dateButton(
                  key: const ValueKey('schedule-date'),
                  label: 'Date de publication',
                  value: _scheduledLocal == null
                      ? 'Choisir'
                      : ChroniqueDateHelper.formatLocal(_scheduledLocal!).split(' • ').first,
                  onPressed: _submitting ? null : _pickScheduledDate,
                ),
                const SizedBox(height: AppSpacing.md),
                _dateButton(
                  key: const ValueKey('schedule-time'),
                  label: 'Heure',
                  value: _scheduledLocal == null
                      ? 'Choisir'
                      : ChroniqueDateHelper.formatLocal(_scheduledLocal!).split(' • ').last,
                  onPressed: _submitting ? null : _pickScheduledTime,
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              _sectionTitle('Expiration', colors.textSecondary),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<ChroniqueExpirationPreset>(
                key: const ValueKey('expiration-dropdown'),
                value: _expiration,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final preset in ChroniqueExpirationPreset.values)
                    DropdownMenuItem(
                      value: preset,
                      child: Text(ChroniqueDateHelper.expirationLabel(preset)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _expiration = value;
                          if (value == ChroniqueExpirationPreset.custom) {
                            _customExpiresLocal ??= DateTime.now();
                          }
                        });
                      },
              ),
              if (_expiration == ChroniqueExpirationPreset.custom) ...[
                const SizedBox(height: AppSpacing.md),
                _dateButton(
                  key: const ValueKey('expires-date'),
                  label: 'Date d\'expiration',
                  value: _customExpiresLocal == null
                      ? 'Choisir'
                      : ChroniqueDateHelper.formatLocal(_customExpiresLocal!).split(' • ').first,
                  onPressed: _submitting ? null : _pickExpiresDate,
                ),
                const SizedBox(height: AppSpacing.md),
                _dateButton(
                  key: const ValueKey('expires-time'),
                  label: 'Heure d\'expiration',
                  value: _customExpiresLocal == null
                      ? 'Choisir'
                      : ChroniqueDateHelper.formatLocal(_customExpiresLocal!).split(' • ').last,
                  onPressed: _submitting ? null : _pickExpiresTime,
                ),
              ],
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
