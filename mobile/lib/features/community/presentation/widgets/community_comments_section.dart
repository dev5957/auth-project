import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../auth/providers/auth_controller.dart';
import '../../../auth/state/auth_state.dart';
import '../../../chronique/models/chronique_date.dart';
import '../../models/community.dart';
import '../../models/community_comment.dart';
import '../state/community_comments_controller.dart';

class CommunityCommentsSection extends ConsumerStatefulWidget {
  const CommunityCommentsSection({
    super.key,
    required this.communityId,
    required this.publicationId,
    required this.commentsEnabled,
    required this.isPublicationAuthor,
    this.myRole,
    this.onCountDelta,
    this.keyPrefix = 'community',
  });

  final int communityId;
  final int publicationId;
  final bool commentsEnabled;
  final bool isPublicationAuthor;
  final CommunityRole? myRole;
  final ValueChanged<int>? onCountDelta;
  final String keyPrefix;

  @override
  ConsumerState<CommunityCommentsSection> createState() => _CommunityCommentsSectionState();
}

class _CommunityCommentsSectionState extends ConsumerState<CommunityCommentsSection> {
  final _controller = TextEditingController();
  String? _composeError;
  CommunityComment? _replyTo;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_clearComposeErrorWhenValid);
  }

  void _clearComposeErrorWhenValid() {
    if (_composeError == null) {
      return;
    }
    if (CommunityCommentFields.bodyError(_controller.text) == null) {
      setState(() => _composeError = null);
    }
  }

  CommunityCommentsKey get _key => (
        communityId: widget.communityId,
        publicationId: widget.publicationId,
      );

  int? get _viewerId {
    final auth = ref.read(authControllerProvider);
    if (auth is AuthAuthenticated) {
      return auth.user.id;
    }
    return null;
  }

  bool get _isModerator {
    final role = widget.myRole;
    return role == CommunityRole.owner || role == CommunityRole.admin;
  }

  bool get _canModerate => _isModerator || widget.isPublicationAuthor;

  bool get _canRestore => _isModerator || widget.isPublicationAuthor;

  Key _uiKey(String suffix) => ValueKey('${widget.keyPrefix}-$suffix');

  @override
  void dispose() {
    _controller.removeListener(_clearComposeErrorWhenValid);
    _controller.dispose();
    super.dispose();
  }

  int _visibleCount() {
    final state = ref.read(communityCommentsControllerProvider(_key));
    if (state is CommunityCommentsReady) {
      return memberVisibleCommentCount(state.items);
    }
    return 0;
  }

  Future<void> _submit() async {
    final error = CommunityCommentFields.bodyError(_controller.text);
    setState(() => _composeError = error);
    if (error != null) {
      return;
    }
    final before = _visibleCount();
    final parentId = _replyTo?.id;
    final ok = await ref.read(communityCommentsControllerProvider(_key).notifier).create(
          _controller.text.trim(),
          parentCommentId: parentId,
        );
    if (!mounted) {
      return;
    }
    if (ok) {
      _controller.clear();
      setState(() => _replyTo = null);
      widget.onCountDelta?.call(_visibleCount() - before);
    }
  }

  void _startReply(CommunityComment comment) {
    setState(() {
      _replyTo = comment;
      _composeError = null;
    });
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  Future<void> _edit(CommunityComment comment) async {
    final edited = await showDialog<String>(
      context: context,
      builder: (context) {
        final field = TextEditingController(text: comment.body);
        return AlertDialog(
          title: const Text('Modifier le commentaire'),
          content: TextField(
            key: _uiKey('comment-edit-field'),
            controller: field,
            maxLength: 200,
            maxLines: 4,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            TextButton(
              key: _uiKey('comment-edit-save'),
              onPressed: () => Navigator.pop(context, field.text),
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
    if (edited == null || CommunityCommentFields.bodyError(edited) != null) {
      return;
    }
    await ref.read(communityCommentsControllerProvider(_key).notifier).update(
          comment.id,
          edited.trim(),
        );
  }

  Future<void> _delete(CommunityComment comment) async {
    final before = _visibleCount();
    final ok = await ref.read(communityCommentsControllerProvider(_key).notifier).remove(comment.id);
    if (!mounted) {
      return;
    }
    if (!ok) {
      return;
    }
    widget.onCountDelta?.call(_visibleCount() - before);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: _uiKey('comment-deleted'),
        content: const Text('Commentaire supprimé'),
      ),
    );
  }

  Future<void> _restore(CommunityComment comment) async {
    final before = _visibleCount();
    final ok = await ref.read(communityCommentsControllerProvider(_key).notifier).restore(comment.id);
    if (!mounted) {
      return;
    }
    if (ok) {
      widget.onCountDelta?.call(_visibleCount() - before);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final state = ref.watch(communityCommentsControllerProvider(_key));
    final replyTo = _replyTo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xl),
        const Text('Commentaires', style: AppTextTheme.titleSmall),
        const SizedBox(height: AppSpacing.md),
        if (widget.commentsEnabled) ...[
          if (replyTo != null) ...[
            Row(
              key: _uiKey('comment-reply-mode'),
              children: [
                Expanded(
                  child: Text(
                    'Réponse à ${replyTo.author.displayLabel}',
                    key: _uiKey('comment-reply-target'),
                    style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                  ),
                ),
                TextButton(
                  key: _uiKey('comment-reply-cancel'),
                  onPressed: _cancelReply,
                  child: const Text('Annuler'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          AppTextField(
            key: _uiKey('comment-input'),
            controller: _controller,
            hint: replyTo == null ? 'Écrire un commentaire' : 'Écrire une réponse',
            minLines: 2,
            maxLines: 4,
            errorText: _composeError,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: _uiKey('comment-submit'),
            label: replyTo == null ? 'Commenter' : 'Répondre',
            onPressed: _submit,
          ),
          const SizedBox(height: AppSpacing.md),
        ] else
          Text(
            'Les commentaires sont désactivés',
            key: _uiKey('comments-disabled'),
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        switch (state) {
          CommunityCommentsLoading() => const AppLoading(),
          CommunityCommentsError(:final message) => Text(
              message,
              key: _uiKey('comments-error'),
            ),
          CommunityCommentsReady(:final items, :final error) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null)
                  Text(error, style: AppTextTheme.labelSmall.copyWith(color: colors.danger)),
                if (items.where((item) => item.isRoot).isEmpty)
                  Text(
                    'Aucun commentaire',
                    key: _uiKey('comments-empty'),
                    style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                  )
                else
                  for (final row in communityCommentDisplayRows(items))
                    _tile(colors, row.comment, indented: row.indented),
              ],
            ),
        },
      ],
    );
  }

  Widget _tile(LuminaColors colors, CommunityComment item, {required bool indented}) {
    final viewer = _viewerId;
    final isAuthor = viewer != null && item.author.userId == viewer;
    return Padding(
      padding: EdgeInsets.only(
        bottom: AppSpacing.md,
        left: indented ? AppSpacing.xxxl : 0,
      ),
      child: Column(
        key: indented ? _uiKey('comment-reply-indent-${item.id}') : _uiKey('comment-root-${item.id}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.author.displayLabel,
                  style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                ),
              ),
              if (item.isVisible && isAuthor)
                PopupMenuButton<String>(
                  key: _uiKey('comment-author-menu-${item.id}'),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _edit(item);
                    } else if (value == 'delete') {
                      _delete(item);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Modifier')),
                    PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                  ],
                )
              else if (item.isVisible && _canModerate && !isAuthor)
                PopupMenuButton<String>(
                  key: _uiKey('comment-mod-menu-${item.id}'),
                  onSelected: (_) => _delete(item),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'moderate', child: Text('Modérer')),
                  ],
                ),
            ],
          ),
          if (item.isModerated)
            Text(
              'Commentaire masqué',
              key: _uiKey('comment-moderated-${item.id}'),
              style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
            )
          else
            Text(
              item.body,
              key: _uiKey('comment-item-${item.id}'),
              style: AppTextTheme.bodyMedium,
            ),
          if (item.createdAt != null) ...[
            const SizedBox(height: 4),
            Text(
              formatOptionalChroniqueDate(DateTime.tryParse(item.createdAt!)) ?? item.createdAt!,
              key: _uiKey('comment-at-${item.id}'),
              style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
            ),
          ],
          if (item.isRoot && item.isVisible && widget.commentsEnabled)
            TextButton(
              key: _uiKey('comment-reply-${item.id}'),
              onPressed: () => _startReply(item),
              child: const Text('Répondre'),
            ),
          if (item.isModerated && _canRestore)
            TextButton(
              key: _uiKey('comment-restore-${item.id}'),
              onPressed: () => _restore(item),
              child: const Text('Restaurer'),
            ),
        ],
      ),
    );
  }
}
