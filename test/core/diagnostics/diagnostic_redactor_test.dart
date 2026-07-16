import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/diagnostics/diagnostic_redactor.dart';

void main() {
  group('DiagnosticRedactor', () {
    test('redacts bearer tokens', () {
      expect(
        DiagnosticRedactor.redact('Authorization: Bearer abc.def-123'),
        'Authorization: Bearer [REDACTED]',
      );
    });

    test('redacts JWT-like strings', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PYE0d';
      expect(DiagnosticRedactor.redact('token=$jwt'), isNot(contains(jwt)));
      expect(DiagnosticRedactor.redact('token=$jwt'), contains('[REDACTED]'));
    });

    test('redacts email addresses', () {
      expect(
        DiagnosticRedactor.redact('user user@example.com signed in'),
        'user [REDACTED] signed in',
      );
    });

    test('redacts SDP payloads', () {
      final result = DiagnosticRedactor.redact(
        'sdp=v=0 o=- 12345 2 IN IP4 127.0.0.1 candidate:1 1 UDP 1 10.0.0.1 5000 typ host',
      );
      expect(result, isNot(contains('127.0.0.1')));
      expect(result, contains('[REDACTED]'));
    });

    test('redacts ICE candidate lines', () {
      final result = DiagnosticRedactor.redact(
        'candidate:1 1 UDP 2130706431 10.0.0.5 54321 typ host',
      );
      expect(result, isNot(contains('10.0.0.5')));
      expect(result, contains('[REDACTED]'));
    });

    test('leaves ordinary text untouched', () {
      expect(
        DiagnosticRedactor.redact('connecting to wss://example.test/ws'),
        'connecting to wss://example.test/ws',
      );
    });

    test('identifies sensitive property keys', () {
      expect(DiagnosticRedactor.isSensitiveKey('accessToken'), isTrue);
      expect(DiagnosticRedactor.isSensitiveKey('sdp'), isTrue);
      expect(DiagnosticRedactor.isSensitiveKey('iceCandidate'), isTrue);
      expect(DiagnosticRedactor.isSensitiveKey('sessionId'), isFalse);
    });
  });
}
