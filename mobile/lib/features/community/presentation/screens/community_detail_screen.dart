import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../models/community.dart';
import '../state/community_detail_controller.dart';
import '../widgets/community_join_requests_section.dart';
import '../widgets/community_media_placeholder.dart';
import '../widgets/sent_invitations_section.dart';

class CommunityDetailScreen extends ConsumerWidget {
  const CommunityDetailScreen({super.key, required this.communityId});

  final int communityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final state = ref.watch(communityDetailControllerProvider(communityId));

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text('Communauté'),
      ),
      body: SafeArea(
        child: switch (state) {
          CommunityDetailLoading() => const AppLoading(),
          CommunityDetailError(:final message, :final statusCode) => Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Text(
                statusCode == 404
                    ? 'Communauté introuvable'
                    : statusCode == 401
                        ? 'Session expirée'
                        : message,
                key: const ValueKey('community-detail-error'),
              ),
            ),
          CommunityDetailReady(:final data) => ListView(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              children: [
                const CommunityMediaPlaceholder(label: 'Bannière', height: 120),
                const SizedBox(height: AppSpacing.lg),
                const CommunityMediaPlaceholder(label: 'Avatar', height: 72),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  data.community.name,
                  key: const ValueKey('community-detail-name'),
                  style: AppTextTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  data.community.myRole.label,
                  key: const ValueKey('community-detail-role'),
                  style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                ),
                if (data.community.myRole == CommunityRole.owner) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    key: const ValueKey('community-detail-invite'),
                    label: 'Inviter un membre',
                    onPressed: () =>
                        context.push(AppRoutes.communityInviteSearch(data.community.id)),
                  ),
                  SentInvitationsSection(communityId: data.community.id),
                  CommunityJoinRequestsSection(communityId: data.community.id),
                ],
                if (data.community.description != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(data.community.description!),
                ],
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Membres (${data.community.memberCount})',
                  style: AppTextTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                for (final member in data.members)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text('${member.login} · ${member.role.label}'),
                  ),
              ],
            ),
        },
      ),
    );
  }
}
