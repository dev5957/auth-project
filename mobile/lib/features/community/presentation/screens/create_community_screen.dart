import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../models/community_fields.dart';
import '../state/community_list_controller.dart';
import '../state/create_community_controller.dart';

class CreateCommunityScreen extends ConsumerStatefulWidget {
  const CreateCommunityScreen({super.key});

  @override
  ConsumerState<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends ConsumerState<CreateCommunityScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final state = ref.watch(createCommunityControllerProvider);

    ref.listen(createCommunityControllerProvider, (previous, next) {
      if (next is CreateCommunitySuccess && mounted) {
        ref.read(communityListControllerProvider.notifier).load();
        context.pop();
      }
    });

    final idle = state is CreateCommunityIdle ? state : null;
    final submitting = state is CreateCommunitySubmitting;
    final error = state is CreateCommunityError ? state : null;

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text('Nouvelle communauté'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          children: [
            AppTextField(
              key: const ValueKey('community-name-field'),
              label: 'Nom',
              controller: _name,
              errorText: idle?.nameError,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              key: const ValueKey('community-description-field'),
              label: 'Description (facultatif)',
              controller: _description,
              errorText: idle?.descriptionError,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
            ),
            if (error != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                error.statusCode == 401 ? 'Session expirée' : error.message,
                key: const ValueKey('community-create-error'),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            AppButton(
              key: const ValueKey('community-create-submit'),
              label: 'Créer',
              isLoading: submitting,
              onPressed: submitting
                  ? null
                  : () {
                      ref.read(createCommunityControllerProvider.notifier).submit(
                            name: CommunityFields.trimmedName(_name.text),
                            description: _description.text,
                          );
                    },
            ),
          ],
        ),
      ),
    );
  }
}
