import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../auth/providers/auth_controller.dart';
import '../../../auth/state/auth_state.dart';
import '../../../chronique/presentation/widgets/chronique_ready_remote_media_list.dart';
import '../../models/community.dart';
import '../../models/community_publication.dart';
import '../../providers/community_providers.dart';
import '../state/community_detail_controller.dart';
import '../state/community_feed_controller.dart';

class CommunityPublicationDetailScreen extends ConsumerStatefulWidget {
  const CommunityPublicationDetailScreen({
    super.key,
    required this.communityId,
    required this.publicationId,
    this.fromMe = false,
  });

  final int communityId;
  final int publicationId;
  final bool fromMe;

  @override
  ConsumerState<CommunityPublicationDetailScreen> createState() =>
      _CommunityPublicationDetailScreenState();
}

class _CommunityPublicationDetailScreenState
    extends ConsumerState<CommunityPublicationDetailScreen> {
  CommunityPublication? _publication;
  String? _error;
  bool _busy = false;

  int? get _viewerId {
    final auth = ref.read(authControllerProvider);
    if (auth is AuthAuthenticated) {
      return auth.user.id;
    }
    return null;
  }

  CommunityRole? get _myRole {
    final detail = ref.read(communityDetailControllerProvider(widget.communityId));
    if (detail is CommunityDetailReady) {
      return detail.data.community.myRole;
    }
    return null;
  }

  bool get _isAuthor {
    final viewer = _viewerId;
    final publication = _publication;
    return viewer != null && publication != null && publication.author.userId == viewer;
  }

  bool get _isModerator {
    final role = _myRole;
    return role == CommunityRole.owner || role == CommunityRole.admin;
  }

  bool get _readOnlyLeft => widget.fromMe && (_publication?.author.isFormerMember ?? false);

  bool get _canEdit => !widget.fromMe && _isAuthor && !_readOnlyLeft && _publication?.status != 'expired';

  bool get _canDelete {
    if (widget.fromMe || _readOnlyLeft) {
      return false;
    }
    final status = _publication?.status;
    if (status == 'active') {
      return _isAuthor || _isModerator;
    }
    if (status == 'scheduled') {
      return _isAuthor;
    }
    return false;
  }

  bool get _canRestore {
    if (widget.fromMe || _readOnlyLeft) {
      return false;
    }
    final publication = _publication;
    if (publication == null || publication.status != 'deleted') {
      return false;
    }
    return _isAuthor && publication.deletedByUserId == _viewerId;
  }

  bool get _canDeleteMedia =>
      !widget.fromMe &&
      _isAuthor &&
      !_readOnlyLeft &&
      (_publication?.status == 'active' || _publication?.status == 'scheduled');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  Future<void> _load() async {
    try {
      final CommunityPublication fresh;
      if (widget.fromMe) {
        fresh = await ref.read(communityRepositoryProvider).getMyPublication(widget.publicationId);
      } else {
        fresh = await ref.read(communityRepositoryProvider).getPublication(
              communityId: widget.communityId,
              publicationId: widget.publicationId,
            );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _publication = fresh;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.message.trim().isEmpty ? 'Unexpected error' : error.message);
    } on FormatException {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Unexpected error');
    }
  }

  Future<void> _edit() async {
    final current = _publication;
    if (current == null) {
      return;
    }
    final updated = await context.push<CommunityPublication>(
      AppRoutes.communityPublicationEdit(widget.communityId, current.id),
      extra: current,
    );
    if (!mounted || updated == null) {
      return;
    }
    setState(() => _publication = updated);
    ref.read(communityFeedControllerProvider(widget.communityId).notifier).load();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la publication ?'),
        content: Text(
          _publication?.status == 'scheduled'
              ? 'Elle ne sera plus programmée.'
              : 'Elle disparaîtra du fil.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(communityRepositoryProvider).deletePublication(
            communityId: widget.communityId,
            publicationId: widget.publicationId,
          );
      if (!mounted) {
        return;
      }
      final wasAuthor = _isAuthor;
      final repository = ref.read(communityRepositoryProvider);
      final feed = ref.read(communityFeedControllerProvider(widget.communityId).notifier);
      await feed.load();
      if (!mounted) {
        return;
      }
      if (wasAuthor) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Publication supprimée'),
            action: SnackBarAction(
              key: const ValueKey('community-publication-restore-action'),
              label: 'Restaurer',
              onPressed: () {
                unawaited(() async {
                  try {
                    await repository.restorePublication(
                      communityId: widget.communityId,
                      publicationId: widget.publicationId,
                    );
                    await feed.load();
                  } catch (_) {}
                }());
              },
            ),
          ),
        );
      }
      context.pop();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  Future<void> _restoreFromScreen() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final restored = await ref.read(communityRepositoryProvider).restorePublication(
            communityId: widget.communityId,
            publicationId: widget.publicationId,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _publication = restored;
      });
      ref.read(communityFeedControllerProvider(widget.communityId).notifier).load();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  Future<void> _deleteMedia(int mediaId) async {
    setState(() => _busy = true);
    try {
      await ref.read(communityRepositoryProvider).deletePublicationMedia(
            communityId: widget.communityId,
            publicationId: widget.publicationId,
            mediaId: mediaId,
          );
      await _load();
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final publication = _publication;
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text('Publication'),
        actions: [
          if (_canEdit || _canDelete)
            PopupMenuButton<String>(
              key: const ValueKey('community-publication-menu'),
              onSelected: (value) {
                if (value == 'edit') {
                  _edit();
                } else if (value == 'delete') {
                  _delete();
                }
              },
              itemBuilder: (context) => [
                if (_canEdit)
                  const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                if (_canDelete)
                  const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: _error != null && publication == null
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Text(_error!, key: const ValueKey('community-publication-error')),
              )
            : publication == null
                ? const AppLoading()
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    children: [
                      Text(
                        publication.author.displayLabel,
                        key: const ValueKey('community-publication-author'),
                        style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                      ),
                      if (publication.communityName != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          publication.communityName!,
                          style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                        ),
                      ],
                      if (publication.title != null && publication.title!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(publication.title!, style: AppTextTheme.titleMedium),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Text(publication.body, style: AppTextTheme.bodyMedium),
                      if (publication.media.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xl),
                        ChroniqueReadyRemoteMediaList(medias: publication.media),
                        if (_canDeleteMedia)
                          for (final media in publication.media)
                            if (media.id != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  key: ValueKey('community-media-delete-${media.id}'),
                                  onPressed: _busy ? null : () => _deleteMedia(media.id!),
                                  child: Text('Supprimer le média ${media.originalFilename ?? media.id}'),
                                ),
                              ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(_error!, style: AppTextTheme.labelSmall.copyWith(color: colors.danger)),
                      ],
                      if (_canRestore) ...[
                        const SizedBox(height: AppSpacing.xl),
                        AppButton(
                          key: const ValueKey('community-publication-restore'),
                          label: 'Restaurer',
                          onPressed: _busy ? null : _restoreFromScreen,
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }
}
