/// Strips secrets, SDP/ICE payloads and emails out of log lines before they
/// reach memory or disk. Mirrors windows_SonicRelay's DiagnosticRedactor rules.
///
/// Note: Dart's RegExp (ECMAScript-flavored) has no inline `(?i)` case flag —
/// unlike .NET's regex engine that windows_SonicRelay's redactor uses. Each
/// case-insensitive pattern here uses the `caseSensitive: false` constructor
/// parameter instead.
class DiagnosticRedactor {
  const DiagnosticRedactor._();

  static const _redacted = '[REDACTED]';

  static final _bearerToken = RegExp(
    r'\bbearer\s+[^\s,;]+',
    caseSensitive: false,
  );
  static final _jwt = RegExp(
    r'\bey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b',
  );
  static final _email = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );
  static final _sdpPayload = RegExp(
    r'\bsdp\s*=\s*.*',
    caseSensitive: false,
  );
  static final _iceCandidate = RegExp(
    r'candidate:[^\r\n]+',
    caseSensitive: false,
  );
  static final _sensitiveAssignment = RegExp(
    r'\b(password|access[_-]?token|refresh[_-]?token|token|code)\s*=\s*[^\s&]+',
    caseSensitive: false,
  );
  static final _sensitiveKey = RegExp(
    r'^(password|access[_-]?token|refresh[_-]?token|token|authorization|sdp|ice[_-]?candidate)$',
    caseSensitive: false,
  );

  static String redact(String? value) {
    if (value == null || value.isEmpty) return value ?? '';
    var result = value.replaceAllMapped(
      _sensitiveAssignment,
      (match) => '${match[1]}=$_redacted',
    );
    result = result.replaceAll(_bearerToken, 'Bearer $_redacted');
    result = result.replaceAll(_jwt, _redacted);
    result = result.replaceAll(_email, _redacted);
    result = result.replaceAll(_sdpPayload, 'sdp=$_redacted');
    result = result.replaceAll(_iceCandidate, _redacted);
    return result;
  }

  static bool isSensitiveKey(String key) => _sensitiveKey.hasMatch(key);
}
