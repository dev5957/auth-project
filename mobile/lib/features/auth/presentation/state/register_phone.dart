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

/// Masque partiel pour l’affichage Step 4 (dernier 4 caractères visibles).
String maskRegisterPhoneNumber(String raw) {
  final phone = normalizeRegisterPhoneNumber(raw);
  if (phone.length <= 4) {
    return phone;
  }
  final last4 = phone.substring(phone.length - 4);
  final prefix = phone.startsWith('+') ? '+' : '';
  final maskedCount = phone.length - prefix.length - 4;
  return '$prefix${'•' * maskedCount}$last4';
}
