import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ForgotPasswordStep { phone, code, password }

class ForgotPasswordFlowState {
  const ForgotPasswordFlowState({
    this.phoneNumber = '',
    this.code,
    this.genericMessage,
    this.step = ForgotPasswordStep.phone,
  });

  final String phoneNumber;
  final String? code;
  final String? genericMessage;
  final ForgotPasswordStep step;

  ForgotPasswordFlowState copyWith({
    String? phoneNumber,
    String? code,
    String? genericMessage,
    ForgotPasswordStep? step,
  }) {
    return ForgotPasswordFlowState(
      phoneNumber: phoneNumber ?? this.phoneNumber,
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

  void savePhone({required String phoneNumber, required String genericMessage}) {
    state = ForgotPasswordFlowState(
      phoneNumber: phoneNumber,
      genericMessage: genericMessage,
      step: ForgotPasswordStep.code,
    );
  }

  void saveCode(String code) {
    state = state.copyWith(code: code, step: ForgotPasswordStep.password);
  }

  void goToPreviousStep() {
    final previous = switch (state.step) {
      ForgotPasswordStep.phone => ForgotPasswordStep.phone,
      ForgotPasswordStep.code => ForgotPasswordStep.phone,
      ForgotPasswordStep.password => ForgotPasswordStep.code,
    };
    state = state.copyWith(step: previous);
  }
}

final forgotPasswordFlowProvider =
    NotifierProvider<ForgotPasswordFlowController, ForgotPasswordFlowState>(
  ForgotPasswordFlowController.new,
);
