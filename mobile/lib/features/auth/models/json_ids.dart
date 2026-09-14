/// `BIGINT` Postgres peut arriver en `num` (doc) ou en `String` (node-pg).
int parseJsonInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw const FormatException('Invalid integer id');
}
