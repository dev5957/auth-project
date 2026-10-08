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
import '../../../chronique/models/chronique_correction_window.dart';
import '../../../chronique/models/chronique_date.dart';
import '../../../chronique/models/chronique_fields.dart';
import '../../../chronique/presentation/widgets/chronique_ready_remote_media_list.dart';
import '../../../chronique/presentation/widgets/chronique_title_body_fields.dart';
import '../../models/community.dart';
import '../../models/community_publication.dart';
import '../../providers/community_providers.dart';
import '../state/community_detail_controller.dart';
import '../state/community_feed_controller.dart';
import '../state/community_publication_sync.dart';
import '../state/my_community_publications_controller.dart';
import '../widgets/community_comments_section.dart';
import '../widgets/community_publication_deleted_snackbar.dart';
import '../widgets/community_publication_social_bar.dart';

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
  bool _editing = false;
  bool _submitting = false;
  TextEditingController? _titleController;
  TextEditingController? _bodyController;
  String? _titleError;
  String? _bodyError;

  int? get _viewerId {
    final auth = ref.read(authControllerProvider);
    if (auth is AuthAuthenticated) {
      return auth.user.id;
    }
    return null;
  }

  CommunityRole? get _myRole {
    return ref.watch(
      communityDetailControllerProvider(widget.communityId).select((state) {
        if (state is CommunityDetailReady) {
          return state.data.community.myRole;
        }
        return null;
      }),
    );
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

  bool get _readOnlyLeft => _publication?.author.isFormerMember ?? false;

  bool get _canEdit {
    if (!_isAuthor || _readOnlyLeft) {
      return false;
    }
    final publication = _publication;
    if (publication == null) {
      return false;
    }
    if (publication.status == 'scheduled') {
      return true;
    }
    if (publication.status == 'active') {
      return isChroniqueTextCorrectionOpen(publication.asChronique());
    }
    return false;
  }

  bool get _canDelete {
    if (_readOnlyLeft) {
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
    if (_readOnlyLeft) {
      return false;
    }
    final publication = _publication;
    if (publication == null || publication.status != 'deleted') {
      return false;
    }
    return _isAuthor && publication.deletedByUserId == _viewerId;
  }

  bool get _canDeleteMedia {
    if (!_isAuthor || _readOnlyLeft || _editing) {
      return false;
    }
    final publication = _publication;
    if (publication == null) {
      return false;
    }
    if (publication.status != 'active' && publication.status != 'scheduled') {
      return false;
    }
    return isChroniqueTextCorrectionOpen(publication.asChronique());
  }

  void _syncPublication(CommunityPublicationInteractionPatch patch) {
    final publication = _publication;
    if (publication == null) {
      return;
    }
    syncCommunityPublication(
      ref,
      publicationId: publication.id,
      communityId: publication.communityId,
      patch: patch,
    );
  }

  Future<void> _reloadRelatedLists() async {
    if (widget.communityId > 0) {
      await ref.read(communityFeedControllerProvider(widget.communityId).notifier).load();
    }
    await ref.read(myCommunityPublicationsControllerProvider('current').notifier).load();
    await ref.read(myCommunityPublicationsControllerProvider('left').notifier).load();
    await ref.read(myCommunityPublicationsControllerProvider('expired').notifier).load();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  @override
  void dispose() {
    _disposeEditControllers();
    super.dispose();
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
    final current = _publication;
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
    final current = _publication;
    if (current == null || _busy || _editing) {
      return;
    }
    if (!isChroniqueTextCorrectionOpen(current.asChronique())) {
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
    if (current.status == 'scheduled') {
      final updated = await context.push<CommunityPublication>(
        AppRoutes.communityPublicationEdit(widget.communityId, current.id),
        extra: current,
      );
      if (!mounted || updated == null) {
        return;
      }
      setState(() => _publication = updated);
      await _reloadRelatedLists();
      return;
    }
    _enterEdit();
  }

  Future<void> _saveEdit() async {
    final current = _publication;
    final titleCtrl = _titleController;
    final bodyCtrl = _bodyController;
    if (current == null || titleCtrl == null || bodyCtrl == null) {
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
      final updated = await ref.read(communityRepositoryProvider).patchPublication(
            communityId: current.communityId,
            publicationId: current.id,
            title: ChroniqueFields.trimmedTitle(titleCtrl.text),
            body: ChroniqueFields.trimmedBody(bodyCtrl.text),
          );
      if (!mounted) {
        return;
      }
      _disposeEditControllers();
      setState(() {
        _publication = updated;
        _editing = false;
        _submitting = false;
        _error = null;
      });
      await _reloadRelatedLists();
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
        await _load();
        return;
      }
      setState(() {
        _submitting = false;
        _error = error.message;
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
      final communityId = widget.communityId;
      final publicationId = widget.publicationId;
      final feedController = communityId > 0
          ? ref.read(communityFeedControllerProvider(communityId).notifier)
          : null;
      final currentMine = ref.read(myCommunityPublicationsControllerProvider('current').notifier);
      final leftMine = ref.read(myCommunityPublicationsControllerProvider('left').notifier);
      final expiredMine = ref.read(myCommunityPublicationsControllerProvider('expired').notifier);
      Future<void> reloadLists() async {
        await feedController?.load();
        await currentMine.load();
        await leftMine.load();
        await expiredMine.load();
      }

      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      context.pop();
      if (wasAuthor) {
        showCommunityPublicationDeletedSnackBar(
          messenger: messenger,
          onRestore: () async {
            await repository.restorePublication(
              communityId: communityId,
              publicationId: publicationId,
            );
            await reloadLists();
          },
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Publication supprimée')),
        );
      }
      unawaited(reloadLists());
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
      await _reloadRelatedLists();
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

  Future<void> _toggleLike() async {
    final publication = _publication;
    if (publication == null || publication.status != 'active') {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = publication.likedByMe
          ? await ref.read(communityRepositoryProvider).unlikePublication(
                communityId: widget.communityId,
                publicationId: widget.publicationId,
              )
          : await ref.read(communityRepositoryProvider).likePublication(
                communityId: widget.communityId,
                publicationId: widget.publicationId,
              );
      if (!mounted) {
        return;
      }
      final updated = publication.copyWith(
        likedByMe: result.likedByMe,
        likeCount: result.likeCount,
      );
      setState(() {
        _busy = false;
        _publication = updated;
      });
      _syncPublication(
        CommunityPublicationInteractionPatch(
          likedByMe: result.likedByMe,
          likeCount: result.likeCount,
        ),
      );
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
          title: Text(_editing ? 'Modifier la publication' : 'Publication'),
          actions: [
            if (_editing)
              TextButton(
                onPressed: _submitting ? null : _exitEdit,
                child: const Text('Annuler'),
              ),
            if (!_editing && (_canEdit || _canDelete))
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
                  : Column(
                      children: [
                        Expanded(
                          child: ListView(
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
                              if (_editing &&
                                  _titleController != null &&
                                  _bodyController != null) ...[
                                const SizedBox(height: AppSpacing.md),
                                ChroniqueTitleBodyFields(
                                  titleController: _titleController!,
                                  bodyController: _bodyController!,
                                  titleError: _titleError,
                                  bodyError: _bodyError,
                                  enabled: !_submitting,
                                ),
                              ] else ...[
                                if (publication.title != null && publication.title!.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  Text(publication.title!, style: AppTextTheme.titleMedium),
                                ],
                                const SizedBox(height: AppSpacing.md),
                                Text(publication.body, style: AppTextTheme.bodyMedium),
                              ],
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
                                          onPressed:
                                              _busy ? null : () => _deleteMedia(media.id!),
                                          child: Text(
                                            'Supprimer le média ${media.originalFilename ?? media.id}',
                                          ),
                                        ),
                                      ),
                              ],
                              if (publication.status == 'expired')
                                ..._expiredHistory(publication, colors),
                              if (publication.status == 'active') ...[
                                const SizedBox(height: AppSpacing.md),
                                CommunityPublicationSocialBar(
                                  publication: publication,
                                  likeEnabled: !_busy && !_submitting,
                                  onLike: _toggleLike,
                                ),
                                CommunityCommentsSection(
                                  communityId: widget.communityId,
                                  publicationId: widget.publicationId,
                                  commentsEnabled: publication.commentsEnabled,
                                  isPublicationAuthor: _isAuthor,
                                  myRole: _myRole,
                                  onCountDelta: (delta) {
                                    final current = _publication;
                                    if (current == null) {
                                      return;
                                    }
                                    final updated = current.copyWith(
                                      commentCount: (current.commentCount + delta).clamp(0, 1 << 30),
                                    );
                                    setState(() => _publication = updated);
                                    _syncPublication(
                                      CommunityPublicationInteractionPatch(
                                        commentCount: updated.commentCount,
                                      ),
                                    );
                                  },
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  _error!,
                                  style: AppTextTheme.labelSmall.copyWith(color: colors.danger),
                                ),
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
                        if (_editing)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.xxl,
                              AppSpacing.md,
                              AppSpacing.xxl,
                              AppSpacing.lg,
                            ),
                            child: AppButton(
                              key: const ValueKey('community-publication-save'),
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

  List<Widget> _expiredHistory(CommunityPublication publication, LuminaColors colors) {
    final style = AppTextTheme.labelSmall.copyWith(color: colors.textSecondary);
    final published = formatOptionalChroniqueDate(
      publication.publishedAt == null ? null : DateTime.tryParse(publication.publishedAt!),
    );
    final expired = formatOptionalChroniqueDate(
      publication.expiredAt == null ? null : DateTime.tryParse(publication.expiredAt!),
    );
    return [
      const SizedBox(height: AppSpacing.xl),
      Text('Expirée', key: const ValueKey('community-publication-expired'), style: style),
      if (published != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Publiée le $published',
          key: const ValueKey('community-publication-published-at'),
          style: style,
        ),
      ],
      if (expired != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Expirée le $expired',
          key: const ValueKey('community-publication-expired-at'),
          style: style,
        ),
      ],
      const SizedBox(height: AppSpacing.sm),
      Text(
        '${publication.likeCount} j’aime · ${publication.commentCount} commentaires',
        key: const ValueKey('community-publication-expired-counts'),
        style: style,
      ),
    ];
  }
}
