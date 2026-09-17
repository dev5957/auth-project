import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_logo.dart';
import '../state/register_flow_controller.dart';
import '../state/register_form_data.dart';
import '../widgets/register_account_step.dart';
import '../widgets/register_personal_step.dart';
import '../widgets/register_phone_step.dart';
import '../widgets/register_verify_phone_step.dart';

/// Coquille Sign Up multi-step. Personal + Account + Phone ; OTP plus tard.
class RegisterScreen extends ConsumerWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.luminaColors;
    final step = ref.watch(registerFlowProvider.select((state) => state.step));

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _onBack(context, ref, step),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Column(
            children: [
              const AppLogo(size: 56),
              const SizedBox(height: AppSpacing.xxl),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offset, child: child),
                  );
                },
                child: switch (step) {
                  RegisterStep.personal => RegisterPersonalStep(
                      key: const ValueKey(RegisterStep.personal),
                      onContinue: () {
                        ref.read(registerFlowProvider.notifier).goToNextStep();
                      },
                    ),
                  RegisterStep.account => RegisterAccountStep(
                      key: const ValueKey(RegisterStep.account),
                      onContinue: () {
                        ref.read(registerFlowProvider.notifier).goToNextStep();
                      },
                    ),
                  RegisterStep.phone => RegisterPhoneStep(
                      key: const ValueKey(RegisterStep.phone),
                      onCodeSent: () {
                        ref.read(registerFlowProvider.notifier).goToNextStep();
                      },
                    ),
                  RegisterStep.verifyPhone => const RegisterVerifyPhoneStep(
                      key: ValueKey(RegisterStep.verifyPhone),
                    ),
                },
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  void _onBack(BuildContext context, WidgetRef ref, RegisterStep step) {
    if (step == RegisterStep.personal) {
      context.pop();
      return;
    }
    ref.read(registerFlowProvider.notifier).goToPreviousStep();
  }
}
