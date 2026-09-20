import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ForgotPasswordStep { email, code, password }

class ForgotPasswordFlowState {
  const ForgotPasswordFlowState({
    this.email = '',
    this.code,
    this.genericMessage,
    this.step = ForgotPasswordStep.email,
  });

  final String email;
  final String? code;
  final String? genericMessage;
  final ForgotPasswordStep step;

  ForgotPasswordFlowState copyWith({
    String? email,
    String? code,
    String? genericMessage,
    ForgotPasswordStep? step,
  }) {
    return ForgotPasswordFlowState(
      email: email ?? this.email,
      code: code ?? this.code,
      genericMessage: genericMessage ?? this.genericMessage,
      step: step ?? this.step,
    );
  }
}

class ForgotPasswordFlowController extends Notifier<ForgotPasswordFlowState> {
  @override
  ForgotPasswordFlowState build() => const ForgotPasswordFlowState();

  void reset() {
    state = const ForgotPasswordFlowState();
  }

  void saveEmail({required String email, required String genericMessage}) {
    state = ForgotPasswordFlowState(
      email: email,
      genericMessage: genericMessage,
      step: ForgotPasswordStep.code,
    );
  }

  void saveCode(String code) {
    state = state.copyWith(code: code, step: ForgotPasswordStep.password);
  }

  void goToPreviousStep() {
    final previous = switch (state.step) {
      ForgotPasswordStep.email => ForgotPasswordStep.email,
      ForgotPasswordStep.code => ForgotPasswordStep.email,
      ForgotPasswordStep.password => ForgotPasswordStep.code,
    };
    state = state.copyWith(step: previous);
  }
}

final forgotPasswordFlowProvider =
    NotifierProvider<ForgotPasswordFlowController, ForgotPasswordFlowState>(
  ForgotPasswordFlowController.new,
);
