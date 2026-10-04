import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../chronique/models/chronique_date.dart';
import '../../models/community_publication.dart';
import '../state/my_community_publications_controller.dart';

class MyCommunityPublicationsScreen extends ConsumerStatefulWidget {
  const MyCommunityPublicationsScreen({super.key});

  @override
  ConsumerState<MyCommunityPublicationsScreen> createState() =>
      _MyCommunityPublicationsScreenState();
}

class _MyCommunityPublicationsScreenState extends ConsumerState<MyCommunityPublicationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text('Mes publications communautaires'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(key: ValueKey('me-pubs-current'), text: 'Actuelles'),
            Tab(key: ValueKey('me-pubs-left'), text: 'Quittées'),
            Tab(key: ValueKey('me-pubs-expired'), text: 'Expirées'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _MeScopeList(scope: 'current'),
          _MeScopeList(scope: 'left'),
          _MeScopeList(scope: 'expired'),
        ],
      ),
    );
  }
}

class _MeScopeList extends ConsumerWidget {
  const _MeScopeList({required this.scope});

  final String scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final state = ref.watch(myCommunityPublicationsControllerProvider(scope));
    return switch (state) {
      MyCommunityPublicationsLoading() => const AppLoading(),
      MyCommunityPublicationsError(:final message) => Center(
          child: Text(message, key: ValueKey('me-pubs-error-$scope')),
        ),
      MyCommunityPublicationsReady(:final items) => items.isEmpty
          ? Center(
              child: Text(
                'Aucune publication',
                key: ValueKey('me-pubs-empty-$scope'),
                style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: AppCard(
                      child: InkWell(
                        key: ValueKey('me-pub-$scope-${item.id}'),
                        onTap: () => _open(context, item),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ..._scheduledLines(item, colors),
                            if (item.communityName != null)
                              Text(
                                item.communityName!,
                                style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                              ),
                            if (item.title != null && item.title!.isNotEmpty)
                              Text(item.title!, style: AppTextTheme.titleSmall),
                            Text(item.body, style: AppTextTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    };
  }

  List<Widget> _scheduledLines(CommunityPublication item, LuminaColors colors) {
    if (item.status != 'scheduled') {
      return const [];
    }
    final style = AppTextTheme.labelSmall.copyWith(color: colors.textSecondary);
    final when = formatOptionalChroniqueDate(item.asChronique().scheduledAt);
    return [
      Text(
        'Programmée',
        key: ValueKey('me-pub-scheduled-label-${item.id}'),
        style: style,
      ),
      if (when != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          when,
          key: ValueKey('me-pub-scheduled-at-${item.id}'),
          style: style,
        ),
      ],
      const SizedBox(height: AppSpacing.sm),
    ];
  }

  void _open(BuildContext context, CommunityPublication item) {
    context.push(
      AppRoutes.myCommunityPublicationDetail(item.id),
      extra: item.communityId,
    );
  }
}
