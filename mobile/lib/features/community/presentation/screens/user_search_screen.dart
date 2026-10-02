import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../models/community.dart';
import '../../models/community_fields.dart';
import '../state/user_search_controller.dart';

class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key, required this.communityId});

  final int communityId;

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen> {
  final _query = TextEditingController();
  UserSearchMode _mode = UserSearchMode.login;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _submit() {
    ref.read(userSearchControllerProvider.notifier).submit(_mode, _query.text);
  }

  void _select(UserSearchHit hit) {
    ref.read(userSearchControllerProvider.notifier).select(hit);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final state = ref.watch(userSearchControllerProvider);
    final idle = state is UserSearchIdle ? state : null;
    final loading = state is UserSearchLoading;
    final isPhone = _mode == UserSearchMode.phone;

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text('Inviter un membre'),
        leading: IconButton(
          key: const ValueKey('user-search-back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.communityDetail(widget.communityId));
            }
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<UserSearchMode>(
                    segments: const [
                      ButtonSegment<UserSearchMode>(
                        value: UserSearchMode.login,
                        label: Text('Login', key: ValueKey('user-search-mode-login')),
                      ),
                      ButtonSegment<UserSearchMode>(
                        value: UserSearchMode.phone,
                        label: Text('Téléphone', key: ValueKey('user-search-mode-phone')),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: loading
                        ? null
                        : (next) {
                            if (next.isEmpty) {
                              return;
                            }
                            setState(() => _mode = next.first);
                          },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    key: const ValueKey('user-search-field'),
                    label: isPhone ? 'Numéro de téléphone' : 'Login',
                    controller: _query,
                    errorText: idle?.queryError,
                    keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: loading ? null : (_) => _submit(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    key: const ValueKey('user-search-submit'),
                    label: 'Rechercher',
                    isLoading: loading,
                    onPressed: loading ? null : _submit,
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (state) {
                UserSearchIdle() => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                    child: Text(
                      'Recherchez un utilisateur par login ou par téléphone.',
                      key: ValueKey('user-search-idle'),
                    ),
                  ),
                UserSearchLoading() => const AppLoading(),
                UserSearchEmpty() => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                    child: Text(
                      'Aucun utilisateur trouvé',
                      key: ValueKey('user-search-empty'),
                    ),
                  ),
                UserSearchError(:final message, :final statusCode) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          statusCode == 401 ? 'Session expirée' : message,
                          key: const ValueKey('user-search-error'),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        AppButton(
                          key: const ValueKey('user-search-retry'),
                          label: 'Réessayer',
                          onPressed: () =>
                              ref.read(userSearchControllerProvider.notifier).retry(),
                        ),
                      ],
                    ),
                  ),
                UserSearchReady(:final hit) => _HitCard(
                    hit: hit,
                    onSelect: () => _select(hit),
                  ),
                UserSearchSelected(:final hit) => ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    children: [
                      Text(
                        kUserSearchSelectedNotice,
                        key: const ValueKey('user-search-selected-notice'),
                        style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _HitCard(hit: hit),
                    ],
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HitCard extends StatelessWidget {
  const _HitCard({required this.hit, this.onSelect});

  final UserSearchHit hit;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hit.login,
              key: ValueKey('user-search-item-${hit.userId}'),
              style: AppTextTheme.titleMedium,
            ),
            if (onSelect != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: ValueKey('user-search-select-${hit.userId}'),
                label: 'Sélectionner',
                onPressed: onSelect,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
