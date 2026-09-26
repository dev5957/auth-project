import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/chronique.dart';
import '../../models/chronique_date.dart';
import '../../providers/chronique_providers.dart';
import '../state/chronique_detail_controller.dart';
import '../state/mon_fil_controller.dart';
import '../state/upcoming_chroniques_controller.dart';
import '../widgets/chronique_lifecycle_dialogs.dart';
import '../widgets/chronique_ready_remote_media_list.dart';

enum _DetailAction { edit, archive, delete }

/// Lecture détaillée V1. Menu ⋮ : modifier / archiver / supprimer.
class ChroniqueDetailScreen extends ConsumerStatefulWidget {
  const ChroniqueDetailScreen({
    super.key,
    required this.chroniqueId,
    this.chronique,
  });

  final int? chroniqueId;
  final Chronique? chronique;

  @override
  ConsumerState<ChroniqueDetailScreen> createState() => _ChroniqueDetailScreenState();
}

class _ChroniqueDetailScreenState extends ConsumerState<ChroniqueDetailScreen> {
  Chronique? _chronique;
  String? _error;
  bool _busy = false;

  int? get _id => widget.chroniqueId ?? widget.chronique?.id;

  @override
  void initState() {
    super.initState();
    _chronique = widget.chronique;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFromApi();
    });
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
      final message = error.message.trim();
      setState(() {
        _error = message.isNotEmpty ? message : 'Unexpected error';
      });
    } on FormatException {
      if (!mounted || _chronique != null) {
        return;
      }
      setState(() => _error = 'Unexpected error');
    }
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

  Future<void> _onAction(_DetailAction action) async {
    if (_busy) {
      return;
    }
    switch (action) {
      case _DetailAction.edit:
        await _openEdit();
      case _DetailAction.archive:
        await _confirmArchive();
      case _DetailAction.delete:
        await _confirmDelete();
    }
  }

  Future<void> _openEdit() async {
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
      _chronique = updated;
      _error = null;
    });
    ref.read(monFilControllerProvider.notifier).upsert(updated);
    ref.read(upcomingChroniquesControllerProvider.notifier).upsert(updated);
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
        _error = _messageFor(error);
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
        _error = _messageFor(error);
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

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final fromFil = _resolveFromFil(ref.watch(monFilControllerProvider));
    final resolved = _chronique ?? fromFil ?? widget.chronique;
    final dateLabel = resolved == null ? '' : chroniqueDateLabel(resolved);
    final title = resolved?.title?.trim();

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        title: Text(
          title != null && title.isNotEmpty ? title : 'Chronique',
          style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
        ),
        actions: [
          if (resolved != null &&
              (resolved.status == 'active' || resolved.status == 'scheduled'))
            PopupMenuButton<_DetailAction>(
              key: const ValueKey('chronique-detail-menu'),
              tooltip: 'Actions',
              enabled: !_busy,
              onSelected: _onAction,
              itemBuilder: (context) {
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
              },
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
            : SingleChildScrollView(
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
