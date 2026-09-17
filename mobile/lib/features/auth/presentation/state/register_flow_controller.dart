import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

final registerFlowProvider =
    NotifierProvider<RegisterFlowController, RegisterFlowState>(
  RegisterFlowController.new,
);
