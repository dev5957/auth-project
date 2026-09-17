/// Données locales du Sign Up (4 étapes). Pas un modèle backend.
class RegisterFormData {
  const RegisterFormData({
    this.firstName,
    this.lastName,
    this.birthDate,
    this.login,
    this.email,
    this.confirmEmail,
    this.password,
    this.confirmPassword,
    this.phoneNumber,
    this.verificationToken,
  });

  final String? firstName;
  final String? lastName;
  final DateTime? birthDate;
  final String? login;
  final String? email;
  final String? confirmEmail;
  final String? password;
  final String? confirmPassword;
  final String? phoneNumber;
  final String? verificationToken;

  String? get formattedBirthDate {
    final date = birthDate;
    if (date == null) {
      return null;
    }
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  RegisterFormData copyWith({
    String? firstName,
    String? lastName,
    DateTime? birthDate,
    String? login,
    String? email,
    String? confirmEmail,
    String? password,
    String? confirmPassword,
    String? phoneNumber,
    String? verificationToken,
  }) {
    return RegisterFormData(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      birthDate: birthDate ?? this.birthDate,
      login: login ?? this.login,
      email: email ?? this.email,
      confirmEmail: confirmEmail ?? this.confirmEmail,
      password: password ?? this.password,
      confirmPassword: confirmPassword ?? this.confirmPassword,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      verificationToken: verificationToken ?? this.verificationToken,
    );
  }
}

enum RegisterStep { personal, account, phone, verifyPhone }

class RegisterFlowState {
  const RegisterFlowState({
    this.step = RegisterStep.personal,
    this.data = const RegisterFormData(),
  });

  final RegisterStep step;
  final RegisterFormData data;

  RegisterFlowState copyWith({
    RegisterStep? step,
    RegisterFormData? data,
  }) {
    return RegisterFlowState(
      step: step ?? this.step,
      data: data ?? this.data,
    );
  }
}
