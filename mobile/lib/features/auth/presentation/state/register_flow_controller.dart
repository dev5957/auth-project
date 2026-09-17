import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import 'register_form_data.dart';

/// État local du Sign Up multi-step. Pas d’appel API ici.
class RegisterFlowController extends Notifier<RegisterFlowState> {
  @override
  RegisterFlowState build() => const RegisterFlowState();

  void savePersonal({
    String? firstName,
    String? lastName,
    required DateTime birthDate,
  }) {
    final data = state.data;
    state = state.copyWith(
      data: RegisterFormData(
        firstName: firstName,
        lastName: lastName,
        birthDate: birthDate,
        login: data.login,
        email: data.email,
        confirmEmail: data.confirmEmail,
        password: data.password,
        confirmPassword: data.confirmPassword,
        phoneNumber: data.phoneNumber,
        verificationToken: data.verificationToken,
      ),
    );
  }

  void saveAccount({
    String? login,
    String? email,
    String? confirmEmail,
    String? password,
    String? confirmPassword,
  }) {
    final data = state.data;
    state = state.copyWith(
      data: RegisterFormData(
        firstName: data.firstName,
        lastName: data.lastName,
        birthDate: data.birthDate,
        login: login,
        email: email,
        confirmEmail: confirmEmail,
        password: password,
        confirmPassword: confirmPassword,
        phoneNumber: data.phoneNumber,
        verificationToken: data.verificationToken,
      ),
    );
  }

  void savePhone({String? phoneNumber}) {
    final data = state.data;
    state = state.copyWith(
      data: RegisterFormData(
        firstName: data.firstName,
        lastName: data.lastName,
        birthDate: data.birthDate,
        login: data.login,
        email: data.email,
        confirmEmail: data.confirmEmail,
        password: data.password,
        confirmPassword: data.confirmPassword,
        phoneNumber: phoneNumber,
        verificationToken: data.verificationToken,
      ),
    );
  }

  void saveVerificationToken(String verificationToken) {
    final data = state.data;
    state = state.copyWith(
      data: RegisterFormData(
        firstName: data.firstName,
        lastName: data.lastName,
        birthDate: data.birthDate,
        login: data.login,
        email: data.email,
        confirmEmail: data.confirmEmail,
        password: data.password,
        confirmPassword: data.confirmPassword,
        phoneNumber: data.phoneNumber,
        verificationToken: verificationToken,
      ),
    );
  }

  void goToNextStep() {
    final next = switch (state.step) {
      RegisterStep.personal => RegisterStep.account,
      RegisterStep.account => RegisterStep.phone,
      RegisterStep.phone => RegisterStep.verifyPhone,
      RegisterStep.verifyPhone => RegisterStep.verifyPhone,
    };
    state = state.copyWith(step: next);
  }

  void goToPreviousStep() {
    final previous = switch (state.step) {
      RegisterStep.personal => RegisterStep.personal,
      RegisterStep.account => RegisterStep.personal,
      RegisterStep.phone => RegisterStep.account,
      RegisterStep.verifyPhone => RegisterStep.phone,
    };
    state = state.copyWith(step: previous);
  }

  /// Nouveau parcours Sign Up : étape Personal, formulaire vide.
  /// Ne pas appeler lors d’un retour entre étapes.
  void reset() {
    state = const RegisterFlowState();
  }
}

final registerFlowProvider =
    NotifierProvider<RegisterFlowController, RegisterFlowState>(
  RegisterFlowController.new,
);

/// Démarre un nouveau parcours Sign Up : formulaire vide, puis navigation.
void startNewRegisterFlow(WidgetRef ref, BuildContext context) {
  ref.read(registerFlowProvider.notifier).reset();
  context.push(AppRoutes.register);
}
