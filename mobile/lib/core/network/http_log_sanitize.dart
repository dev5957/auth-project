import 'package:dio/dio.dart';

/// Redaction of sensitive values before HTTP diagnostic logs.
abstract final class HttpLogSanitize {
  static const Set<String> sensitiveQueryKeys = {
    'phone',
    'phone_number',
    'password',
    'new_password',
    'old_password',
    'token',
    'access_token',
    'refresh_token',
    'id_token',
    'authorization',
    'email',
    'login',
    'otp',
    'code',
    'secret',
  };

  static final String _keyAlt = sensitiveQueryKeys.map(RegExp.escape).join('|');

  static final RegExp _jsonQuotedPattern = RegExp(
    '"($_keyAlt)"\\s*:\\s*"(?:\\\\.|[^"\\\\])*"',
    caseSensitive: false,
  );

  static final RegExp _jsonBarePattern = RegExp(
    '"($_keyAlt)"\\s*:\\s*(?!")[^,}\\s]+',
    caseSensitive: false,
  );

  static final RegExp _mapPattern = RegExp(
    '(^|[{\\s,])($_keyAlt)\\s*:\\s*([^,}\\]]*)',
    caseSensitive: false,
  );

  static final RegExp _queryValuePattern = RegExp(
    '($_keyAlt)='
    r'([^&\s"<>]*)',
    caseSensitive: false,
  );

  static final RegExp _bearerPattern = RegExp(
    r'(Bearer)\s+(\S+)',
    caseSensitive: false,
  );

  static final RegExp _authorizationPattern = RegExp(
    r'(Authorization)\s*[:=]\s*\S+',
    caseSensitive: false,
  );

  static bool isSensitiveKey(String key) =>
      sensitiveQueryKeys.contains(key.toLowerCase());

  static Uri uri(Uri raw) {
    if (!raw.hasQuery) {
      return raw;
    }
    final next = <String, String>{};
    raw.queryParametersAll.forEach((key, values) {
      next[key] = isSensitiveKey(key) ? 'REDACTED' : values.join(',');
    });
    return raw.replace(queryParameters: next);
  }

  static String requestUri(RequestOptions options) => uri(options.uri).toString();

  static String text(Object? value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) {
      return raw;
    }
    var out = raw.replaceAllMapped(_jsonQuotedPattern, (match) {
      return '"${match.group(1)}":"REDACTED"';
    });
    out = out.replaceAllMapped(_jsonBarePattern, (match) {
      return '"${match.group(1)}":REDACTED';
    });
    out = out.replaceAllMapped(_mapPattern, (match) {
      return '${match.group(1)}${match.group(2)}: REDACTED';
    });
    out = out.replaceAllMapped(_queryValuePattern, (match) {
      return '${match.group(1)}=REDACTED';
    });
    out = out.replaceAllMapped(_bearerPattern, (match) {
      return '${match.group(1)} REDACTED';
    });
    out = out.replaceAllMapped(_authorizationPattern, (match) {
      return '${match.group(1)}: REDACTED';
    });
    return out;
  }
}
