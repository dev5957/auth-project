import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../models/chronique.dart';
import '../../models/chronique_correction_window.dart';
import '../../models/chronique_date.dart';
import '../../models/chronique_fields.dart';
import '../../providers/chronique_providers.dart';
import '../state/chronique_detail_controller.dart';
import '../state/edit_chronique_controller.dart';
import '../state/mon_fil_controller.dart';
import '../state/upcoming_chroniques_controller.dart';
import '../widgets/chronique_lifecycle_dialogs.dart';
import '../widgets/chronique_ready_remote_media_list.dart';
import '../widgets/chronique_title_body_fields.dart';

enum _DetailAction { edit, archive, delete }

/// Espace auteur : consultation, correction titre/texte, archive/suppression.
class ChroniqueDetailScreen extends ConsumerStatefulWidget {
  const ChroniqueDetailScreen({
    super.key,
    required this.chroniqueId,
    this.chronique,
    this.startEditing = false,
  });

  final int? chroniqueId;
  final Chronique? chronique;
  final bool startEditing;

  @override
  ConsumerState<ChroniqueDetailScreen> createState() => _ChroniqueDetailScreenState();
}

class _ChroniqueDetailScreenState extends ConsumerState<ChroniqueDetailScreen> {
  Chronique? _chronique;
  String? _error;
  bool _busy = false;
  bool _editing = false;
  bool _submitting = false;
  TextEditingController? _titleController;
  TextEditingController? _bodyController;
  String? _titleError;
  String? _bodyError;

  int? get _id => widget.chroniqueId ?? widget.chronique?.id;

  @override
  void initState() {
    super.initState();
    _chronique = widget.chronique;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.startEditing) {
        _enterEdit();
      }
      _loadFromApi();
    });
  }

  @override
  void dispose() {
    _disposeEditControllers();
    super.dispose();
  }

  int _loadGeneration = 0;

  Future<void> _loadFromApi() async {
    final id = _id;
    if (id == null) {
      return;
    }
    final generation = ++_loadGeneration;
    try {
      final fresh = await ref.read(chroniqueRepositoryProvider).get(id);
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _chronique = fresh;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_chronique != null) {
        return;
      }
      setState(() {
        _error = messageForChroniqueApiError(error);
      });
    } on FormatException {
      if (!mounted || _chronique != null) {
        return;
      }
      setState(() => _error = 'Unexpected error');
    }
  }

  void _onEditFields() {
    if (!_editing) {
      return;
    }
    setState(() {
      _titleError = ChroniqueFields.titleError(_titleController?.text ?? '');
      _bodyError = ChroniqueFields.bodyError(_bodyController?.text ?? '');
    });
  }

  void _disposeEditControllers() {
    _titleController?.removeListener(_onEditFields);
    _bodyController?.removeListener(_onEditFields);
    _titleController?.dispose();
    _bodyController?.dispose();
    _titleController = null;
    _bodyController = null;
  }

  bool get _isDirty {
    final current = _chronique;
    final titleCtrl = _titleController;
    final bodyCtrl = _bodyController;
    if (current == null || titleCtrl == null || bodyCtrl == null) {
      return false;
    }
    return ChroniqueFields.trimmedTitle(titleCtrl.text) !=
            ChroniqueFields.trimmedTitle(current.title ?? '') ||
        ChroniqueFields.trimmedBody(bodyCtrl.text) != ChroniqueFields.trimmedBody(current.body);
  }

  bool get _canSave =>
      !_submitting &&
      _isDirty &&
      ChroniqueFields.bodyError(_bodyController?.text ?? '') == null &&
      ChroniqueFields.titleError(_titleController?.text ?? '') == null;

  void _enterEdit() {
    final current = _chronique;
    if (current == null || _busy || _editing) {
      return;
    }
    if (!isChroniqueTextCorrectionOpen(current)) {
      setState(() {
        _error = kCorrectionWindowExpiredUserMessage;
      });
      return;
    }
    _disposeEditControllers();
    final title = TextEditingController(text: current.title ?? '');
    final body = TextEditingController(text: current.body);
    title.addListener(_onEditFields);
    body.addListener(_onEditFields);
    setState(() {
      _titleController = title;
      _bodyController = body;
      _titleError = null;
      _bodyError = null;
      _editing = true;
      _error = null;
    });
  }

  void _exitEdit() {
    _disposeEditControllers();
    setState(() {
      _editing = false;
      _submitting = false;
      _titleError = null;
      _bodyError = null;
    });
  }

  Future<void> _onAction(_DetailAction action) async {
    if (_busy || _editing) {
      return;
    }
    switch (action) {
      case _DetailAction.edit:
        if (_chronique?.status == 'scheduled') {
          await _openScheduledEdit();
        } else {
          _enterEdit();
        }
      case _DetailAction.archive:
        await _confirmArchive();
      case _DetailAction.delete:
        await _confirmDelete();
    }
  }

  Future<void> _openScheduledEdit() async {
    final current = _chronique;
    final id = _id;
    if (current == null || id == null) {
      return;
    }
    final updated = await context.push<Chronique>(
      AppRoutes.chroniqueEdit(id),
      extra: current,
    );
    if (!mounted || updated == null) {
      return;
    }
    _loadGeneration++;
    setState(() {
      _chronique = Chronique.keepExistingMedia(current, updated);
      _error = null;
    });
    ref.read(monFilControllerProvider.notifier).upsert(updated);
    ref.read(upcomingChroniquesControllerProvider.notifier).upsert(updated);
  }

  Future<void> _saveEdit() async {
    final current = _chronique;
    final id = _id;
    final titleCtrl = _titleController;
    final bodyCtrl = _bodyController;
    if (current == null || id == null || titleCtrl == null || bodyCtrl == null) {
      return;
    }
    if (_submitting || !_isDirty) {
      return;
    }
    final bodyError = ChroniqueFields.bodyError(bodyCtrl.text);
    final titleError = ChroniqueFields.titleError(titleCtrl.text);
    setState(() {
      _bodyError = bodyError;
      _titleError = titleError;
    });
    if (bodyError != null || titleError != null) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final updated = await ref.read(editChroniqueControllerProvider.notifier).save(
            id: id,
            body: ChroniqueFields.trimmedBody(bodyCtrl.text),
            title: ChroniqueFields.trimmedTitle(titleCtrl.text),
          );
      if (!mounted) {
        return;
      }
      _disposeEditControllers();
      setState(() {
        _chronique = Chronique.keepExistingMedia(current, updated);
        _editing = false;
        _submitting = false;
        _error = null;
      });
      ref.read(monFilControllerProvider.notifier).upsert(updated);
      ref.read(upcomingChroniquesControllerProvider.notifier).upsert(updated);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.message.trim() == kCorrectionWindowExpiredCode) {
        _disposeEditControllers();
        setState(() {
          _editing = false;
          _submitting = false;
          _error = kCorrectionWindowExpiredUserMessage;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(kCorrectionWindowExpiredUserMessage)),
        );
        await _loadFromApi();
        return;
      }
      setState(() {
        _submitting = false;
        _error = messageForChroniqueApiError(error);
      });
    } on FormatException {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = 'Unexpected error';
      });
    }
  }

  Future<void> _confirmDelete() async {
    final id = _id;
    if (id == null) {
      return;
    }
    final confirmed = await confirmDeleteChronique(
      context,
      scheduled: _chronique?.status == 'scheduled',
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(chroniqueRepositoryProvider).delete(id);
      if (!mounted) {
        return;
      }
      ref.read(monFilControllerProvider.notifier).removeById(id);
      ref.read(upcomingChroniquesControllerProvider.notifier).removeById(id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chronique supprimée')),
      );
      context.pop();
      ref.read(monFilControllerProvider.notifier).refresh();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = messageForChroniqueApiError(error);
      });
    } on FormatException {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = 'Unexpected error';
      });
    }
  }

  Future<void> _confirmArchive() async {
    final id = _id;
    if (id == null) {
      return;
    }
    final confirmed = await confirmArchiveChronique(context);
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(chroniqueDetailControllerProvider.notifier).archive(id);
      if (!mounted) {
        return;
      }
      ref.read(monFilControllerProvider.notifier).removeById(id);
      context.pop();
      ref.read(monFilControllerProvider.notifier).refresh();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = messageForChroniqueApiError(error);
      });
    } on FormatException {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = 'Unexpected error';
      });
    }
  }

  List<PopupMenuEntry<_DetailAction>> _menuItems(Chronique resolved) {
    if (resolved.status == 'scheduled') {
      return const [
        PopupMenuItem(
          value: _DetailAction.edit,
          child: Text('Modifier'),
        ),
        PopupMenuItem(
          value: _DetailAction.delete,
          child: Text('Supprimer'),
        ),
      ];
    }
    if (resolved.status == 'archived' || resolved.status == 'expired') {
      return const <PopupMenuEntry<_DetailAction>>[];
    }
    return [
      if (isChroniqueTextCorrectionOpen(resolved))
        const PopupMenuItem(
          value: _DetailAction.edit,
          child: Text('Modifier'),
        ),
      if (resolved.status == 'active')
        const PopupMenuItem(
          value: _DetailAction.archive,
          child: Text('Archiver'),
        ),
      const PopupMenuItem(
        value: _DetailAction.delete,
        child: Text('Supprimer'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final fromFil = _resolveFromFil(ref.watch(monFilControllerProvider));
    final resolved = _chronique ?? fromFil ?? widget.chronique;
    final dateLabel = resolved == null ? '' : chroniqueDateLabel(resolved);
    final title = resolved?.title?.trim();
    final showMenu = resolved != null &&
        !_editing &&
        (resolved.status == 'active' || resolved.status == 'scheduled');

    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _editing) {
          _exitEdit();
        }
      },
      child: Scaffold(
        backgroundColor: colors.bgBase,
        appBar: AppBar(
          backgroundColor: colors.bgBase,
          foregroundColor: colors.textPrimary,
          elevation: 0,
          title: Text(
            _editing
                ? 'Modifier la chronique'
                : (title != null && title.isNotEmpty ? title : 'Chronique'),
            style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
          ),
          actions: [
            if (_editing)
              TextButton(
                onPressed: _submitting ? null : _exitEdit,
                child: const Text('Annuler'),
              ),
            if (showMenu)
              PopupMenuButton<_DetailAction>(
                key: const ValueKey('chronique-detail-menu'),
                tooltip: 'Actions',
                enabled: !_busy,
                onSelected: _onAction,
                itemBuilder: (context) => _menuItems(resolved),
              ),
          ],
        ),
        body: SafeArea(
          child: resolved == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: Text(
                      _error ?? 'Chronique introuvable',
                      textAlign: TextAlign.center,
                      style: AppTextTheme.bodyMedium.copyWith(
                        color: _error == null ? colors.textSecondary : colors.danger,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.xxl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (dateLabel.isNotEmpty) ...[
                              Text(
                                dateLabel,
                                style: AppTextTheme.labelSmall.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                            ],
                            if (resolved.status == 'scheduled' && resolved.scheduledAt != null) ...[
                              Text(
                                'Programmée le ${ChroniqueDateHelper.formatLocal(resolved.scheduledAt!)}',
                                style: AppTextTheme.labelSmall.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                            ],
                            if (resolved.isTimeLimited && resolved.expiresAt != null) ...[
                              Text(
                                'Expire le ${ChroniqueDateHelper.formatLocal(resolved.expiresAt!)}',
                                style: AppTextTheme.labelSmall.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                            ],
                            if (resolved.status == 'expired') ...[
                              if (chroniqueDefinitiveDeletionLabel(resolved) case final remaining?) ...[
                                Text(
                                  remaining,
                                  key: const ValueKey('chronique-expired-remaining'),
                                  style: AppTextTheme.labelSmall.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                              ],
                            ],
                            if (_editing && _titleController != null && _bodyController != null)
                              ChroniqueTitleBodyFields(
                                titleController: _titleController!,
                                bodyController: _bodyController!,
                                titleError: _titleError,
                                bodyError: _bodyError,
                                enabled: !_submitting,
                              )
                            else ...[
                              if (title != null && title.isNotEmpty) ...[
                                Text(
                                  title,
                                  style: AppTextTheme.titleLarge.copyWith(
                                    color: colors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                              ],
                              Text(
                                resolved.body,
                                style: AppTextTheme.bodyLarge.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                            if (displayableChroniqueRemoteMedia(resolved.media).isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.xxl),
                              ChroniqueReadyRemoteMediaList(medias: resolved.media),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: AppSpacing.lg),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: AppTextTheme.labelSmall.copyWith(color: colors.danger),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_editing)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xxl,
                          AppSpacing.md,
                          AppSpacing.xxl,
                          AppSpacing.lg,
                        ),
                        child: AppButton(
                          label: 'Enregistrer',
                          isLoading: _submitting,
                          onPressed: _canSave ? _saveEdit : null,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Chronique? _resolveFromFil(MonFilState state) {
    final id = _id;
    if (id == null || state is! MonFilReady) {
      return null;
    }
    for (final item in state.items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }
}
