/// Normalisation téléphone alignée sur le backend (`trim`, espaces / tirets / parenthèses).
const int registerPhoneMaxLength = 32;

final _phoneNoise = RegExp(r'[\s\-()]');

String normalizeRegisterPhoneNumber(String raw) {
  return raw.trim().replaceAll(_phoneNoise, '');
}

String? validateRegisterPhoneNumber(String raw) {
  if (raw.trim().isEmpty) {
    return 'Phone number is required';
  }
  final normalized = normalizeRegisterPhoneNumber(raw);
  if (normalized.isEmpty) {
    return 'Phone number is required';
  }
  if (normalized.length > registerPhoneMaxLength) {
    return 'phone_number is invalid';
  }
  return null;
}
