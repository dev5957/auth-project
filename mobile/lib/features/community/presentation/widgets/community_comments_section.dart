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
  });

  final int communityId;
  final int publicationId;
  final bool commentsEnabled;
  final bool isPublicationAuthor;
  final CommunityRole? myRole;
  final ValueChanged<int>? onCountDelta;

  @override
  ConsumerState<CommunityCommentsSection> createState() => _CommunityCommentsSectionState();
}

class _CommunityCommentsSectionState extends ConsumerState<CommunityCommentsSection> {
  final _controller = TextEditingController();
  String? _composeError;

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

  @override
  void dispose() {
    _controller.removeListener(_clearComposeErrorWhenValid);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final error = CommunityCommentFields.bodyError(_controller.text);
    setState(() => _composeError = error);
    if (error != null) {
      return;
    }
    final ok = await ref.read(communityCommentsControllerProvider(_key).notifier).create(
          _controller.text.trim(),
        );
    if (!mounted) {
      return;
    }
    if (ok) {
      _controller.clear();
      widget.onCountDelta?.call(1);
    }
  }

  Future<void> _edit(CommunityComment comment) async {
    final edited = await showDialog<String>(
      context: context,
      builder: (context) {
        final field = TextEditingController(text: comment.body);
        return AlertDialog(
          title: const Text('Modifier le commentaire'),
          content: TextField(
            key: const ValueKey('community-comment-edit-field'),
            controller: field,
            maxLength: 200,
            maxLines: 4,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            TextButton(
              key: const ValueKey('community-comment-edit-save'),
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
    final ok = await ref.read(communityCommentsControllerProvider(_key).notifier).remove(comment.id);
    if (!mounted) {
      return;
    }
    if (!ok) {
      return;
    }
    if (comment.isVisible) {
      widget.onCountDelta?.call(-1);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        key: ValueKey('community-comment-deleted'),
        content: Text('Commentaire supprimé'),
      ),
    );
  }

  Future<void> _restore(CommunityComment comment) async {
    final ok = await ref.read(communityCommentsControllerProvider(_key).notifier).restore(comment.id);
    if (ok) {
      widget.onCountDelta?.call(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final state = ref.watch(communityCommentsControllerProvider(_key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xl),
        const Text('Commentaires', style: AppTextTheme.titleSmall),
        const SizedBox(height: AppSpacing.md),
        if (widget.commentsEnabled) ...[
          AppTextField(
            key: const ValueKey('community-comment-input'),
            controller: _controller,
            hint: 'Écrire un commentaire',
            minLines: 2,
            maxLines: 4,
            errorText: _composeError,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const ValueKey('community-comment-submit'),
            label: 'Commenter',
            onPressed: _submit,
          ),
          const SizedBox(height: AppSpacing.md),
        ] else
          Text(
            'Les commentaires sont désactivés',
            key: const ValueKey('community-comments-disabled'),
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        switch (state) {
          CommunityCommentsLoading() => const AppLoading(),
          CommunityCommentsError(:final message) => Text(
              message,
              key: const ValueKey('community-comments-error'),
            ),
          CommunityCommentsReady(:final items, :final error) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null)
                  Text(error, style: AppTextTheme.labelSmall.copyWith(color: colors.danger)),
                if (items.isEmpty)
                  Text(
                    'Aucun commentaire',
                    key: const ValueKey('community-comments-empty'),
                    style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                  )
                else
                  for (final item in items) _tile(colors, item),
              ],
            ),
        },
      ],
    );
  }

  Widget _tile(LuminaColors colors, CommunityComment item) {
    final viewer = _viewerId;
    final isAuthor = viewer != null && item.author.userId == viewer;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
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
                  key: ValueKey('community-comment-author-menu-${item.id}'),
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
                  key: ValueKey('community-comment-mod-menu-${item.id}'),
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
              key: ValueKey('community-comment-moderated-${item.id}'),
              style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
            )
          else
            Text(
              item.body,
              key: ValueKey('community-comment-item-${item.id}'),
              style: AppTextTheme.bodyMedium,
            ),
          if (item.createdAt != null) ...[
            const SizedBox(height: 4),
            Text(
              formatOptionalChroniqueDate(DateTime.tryParse(item.createdAt!)) ?? item.createdAt!,
              key: ValueKey('community-comment-at-${item.id}'),
              style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
            ),
          ],
          if (item.isModerated && _isModerator)
            TextButton(
              key: ValueKey('community-comment-restore-${item.id}'),
              onPressed: () => _restore(item),
              child: const Text('Restaurer'),
            ),
        ],
      ),
    );
  }
}
