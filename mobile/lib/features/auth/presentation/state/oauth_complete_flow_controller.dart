import 'package:flutter_riverpod/flutter_riverpod.dart';

enum OAuthCompleteStep { phone, otp, birthDate, publicLogin }

class OAuthCompleteFlowState {
  const OAuthCompleteFlowState({
    this.email = '',
    this.oauthVerificationToken = '',
    this.phoneNumber,
    this.otpCode,
    this.birthDate,
    this.publicLogin,
    this.step = OAuthCompleteStep.phone,
  });

  final String email;
  final String oauthVerificationToken;
  final String? phoneNumber;
  final String? otpCode;
  final String? birthDate;
  final String? publicLogin;
  final OAuthCompleteStep step;

  OAuthCompleteFlowState copyWith({
    String? email,
    String? oauthVerificationToken,
    String? phoneNumber,
    String? otpCode,
    String? birthDate,
    String? publicLogin,
    OAuthCompleteStep? step,
  }) {
    return OAuthCompleteFlowState(
      email: email ?? this.email,
      oauthVerificationToken: oauthVerificationToken ?? this.oauthVerificationToken,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      otpCode: otpCode ?? this.otpCode,
      birthDate: birthDate ?? this.birthDate,
      publicLogin: publicLogin ?? this.publicLogin,
      step: step ?? this.step,
    );
  }

  @override
  String toString() =>
      'OAuthCompleteFlowState(email: $email, step: $step, token: (omitted))';
}

class OAuthCompleteFlowController extends Notifier<OAuthCompleteFlowState> {
  @override
  OAuthCompleteFlowState build() => const OAuthCompleteFlowState();

  void start({
    required String email,
    required String oauthVerificationToken,
  }) {
    state = OAuthCompleteFlowState(
      email: email,
      oauthVerificationToken: oauthVerificationToken,
    );
  }

  void replaceOauthVerificationToken(String token) {
    state = state.copyWith(oauthVerificationToken: token);
  }

  void savePhone(String phoneNumber) {
    state = state.copyWith(phoneNumber: phoneNumber, step: OAuthCompleteStep.otp);
  }

  void saveOtp(String code) {
    state = state.copyWith(otpCode: code, step: OAuthCompleteStep.birthDate);
  }

  void saveBirthDate(String birthDate) {
    state = state.copyWith(birthDate: birthDate, step: OAuthCompleteStep.publicLogin);
  }

  void goToPreviousStep() {
    final previous = switch (state.step) {
      OAuthCompleteStep.phone => OAuthCompleteStep.phone,
      OAuthCompleteStep.otp => OAuthCompleteStep.phone,
      OAuthCompleteStep.birthDate => OAuthCompleteStep.otp,
      OAuthCompleteStep.publicLogin => OAuthCompleteStep.birthDate,
    };
    state = state.copyWith(step: previous);
  }

  void reset() {
    state = const OAuthCompleteFlowState();
  }
}

final oauthCompleteFlowProvider =
    NotifierProvider<OAuthCompleteFlowController, OAuthCompleteFlowState>(
  OAuthCompleteFlowController.new,
);
