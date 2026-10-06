import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../models/community.dart';
import '../state/community_detail_controller.dart';
import '../state/community_list_controller.dart';
import '../widgets/community_feed_section.dart';
import '../widgets/community_header.dart';
import '../widgets/community_management_section.dart';
import '../widgets/community_member_dialogs.dart';
import '../widgets/community_members_section.dart';
import '../widgets/community_owner_leave_flow.dart';

class CommunityDetailScreen extends ConsumerWidget {
  const CommunityDetailScreen({super.key, required this.communityId});

  final int communityId;

  Future<void> _onPromote(
    BuildContext context,
    WidgetRef ref,
    CommunityMember member,
  ) async {
    final confirmed = await confirmPromoteMember(context, login: member.login);
    if (!confirmed) {
      return;
    }
    final ok = await ref
        .read(communityDetailControllerProvider(communityId).notifier)
        .updateMemberRole(userId: member.userId, role: 'admin');
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de modifier ce rôle')),
      );
    }
  }

  Future<void> _onDemote(
    BuildContext context,
    WidgetRef ref,
    CommunityMember member,
  ) async {
    final confirmed = await confirmDemoteAdmin(context, login: member.login);
    if (!confirmed) {
      return;
    }
    final ok = await ref
        .read(communityDetailControllerProvider(communityId).notifier)
        .updateMemberRole(userId: member.userId, role: 'member');
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de modifier ce rôle')),
      );
    }
  }

  Future<void> _onRemove(
    BuildContext context,
    WidgetRef ref,
    CommunityMember member,
  ) async {
    final confirmed = await confirmRemoveMember(context, login: member.login);
    if (!confirmed) {
      return;
    }
    final ok = await ref
        .read(communityDetailControllerProvider(communityId).notifier)
        .removeMember(member.userId);
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de retirer ce membre')),
      );
    }
  }

  Future<void> _onLeave(
    BuildContext context,
    WidgetRef ref,
    Community community,
    List<CommunityMember> members,
  ) async {
    final notifier = ref.read(communityDetailControllerProvider(communityId).notifier);
    final left = await runCommunityLeaveFlow(
      context: context,
      myRole: community.myRole,
      members: members,
      updateMemberRole: notifier.updateMemberRole,
      leave: notifier.leave,
      onError: (message) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        }
      },
    );
    if (!left || !context.mounted) {
      return;
    }
    await ref.read(communityListControllerProvider.notifier).load();
    if (!context.mounted) {
      return;
    }
    context.pop();
  }

  Future<void> _returnToCommunityList(BuildContext context, WidgetRef ref) async {
    await ref.read(communityListControllerProvider.notifier).load();
    if (!context.mounted) {
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.communities);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final state = ref.watch(communityDetailControllerProvider(communityId));

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text('Communauté'),
        leading: IconButton(
          key: const ValueKey('community-detail-close'),
          tooltip: 'Retour',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _returnToCommunityList(context, ref),
        ),
      ),
      body: SafeArea(
        child: switch (state) {
          CommunityDetailLoading() => const AppLoading(),
          CommunityDetailError(:final message, :final statusCode) => Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    statusCode == 404
                        ? 'Communauté introuvable'
                        : statusCode == 401
                            ? 'Session expirée'
                            : message,
                    key: const ValueKey('community-detail-error'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    key: const ValueKey('community-detail-error-back'),
                    label: 'Retour aux communautés',
                    onPressed: () => _returnToCommunityList(context, ref),
                  ),
                ],
              ),
            ),
          CommunityDetailReady(:final data) => _CommunityReadyShell(
              data: data,
              onPromote: (member) => _onPromote(context, ref, member),
              onDemote: (member) => _onDemote(context, ref, member),
              onRemove: (member) => _onRemove(context, ref, member),
              onLeave: () => _onLeave(context, ref, data.community, data.members),
            ),
        },
      ),
    );
  }
}

class _CommunityReadyShell extends StatefulWidget {
  const _CommunityReadyShell({
    required this.data,
    required this.onPromote,
    required this.onDemote,
    required this.onRemove,
    required this.onLeave,
  });

  final CommunityDetailData data;
  final ValueChanged<CommunityMember> onPromote;
  final ValueChanged<CommunityMember> onDemote;
  final ValueChanged<CommunityMember> onRemove;
  final VoidCallback onLeave;

  @override
  State<_CommunityReadyShell> createState() => _CommunityReadyShellState();
}

class _CommunityReadyShellState extends State<_CommunityReadyShell>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late bool _canManage;

  bool _manageFor(CommunityRole role) =>
      role == CommunityRole.owner || role == CommunityRole.admin;

  @override
  void initState() {
    super.initState();
    _canManage = _manageFor(widget.data.community.myRole);
    _tabs = TabController(length: _canManage ? 3 : 2, vsync: this);
  }

  @override
  void didUpdateWidget(covariant _CommunityReadyShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final canManage = _manageFor(widget.data.community.myRole);
    if (canManage == _canManage) {
      return;
    }
    _tabs.dispose();
    _canManage = canManage;
    _tabs = TabController(length: _canManage ? 3 : 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final community = widget.data.community;
    final colors = context.luminaColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommunityHeader(community: community),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          labelColor: colors.primary,
          unselectedLabelColor: colors.textSecondary,
          tabs: [
            const Tab(key: ValueKey('community-nav-feed'), text: 'Fil'),
            const Tab(key: ValueKey('community-nav-members'), text: 'Membres'),
            if (_canManage) const Tab(key: ValueKey('community-nav-manage'), text: 'Gestion'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              CommunityFeedSection(community: community),
              CommunityMembersSection(
                community: community,
                members: widget.data.members,
                onPromote: widget.onPromote,
                onDemote: widget.onDemote,
                onRemove: widget.onRemove,
                onLeave: widget.onLeave,
              ),
              if (_canManage) CommunityManagementSection(community: community),
            ],
          ),
        ),
      ],
    );
  }
}
