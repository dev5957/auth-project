/// Initiales affichées depuis le login Auth, sans inventer un nom.
String homeUserInitials(String login) {
  final trimmed = login.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (trimmed.length == 1) {
    return trimmed.toUpperCase();
  }
  return trimmed.substring(0, 2).toUpperCase();
}
