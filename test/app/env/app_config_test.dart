import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/env/app_config.dart';

void main() {
  group('AppConfig.fromServerUrl', () {
    test('derives a wss WebSocket URL from an https server URL', () {
      final config = AppConfig.fromServerUrl(
        'https://sonicRelay-api.hugodotnet.dev',
      );

      expect(config.apiBaseUrl, 'https://sonicRelay-api.hugodotnet.dev');
      expect(config.webSocketBaseUrl, 'wss://sonicRelay-api.hugodotnet.dev');
      // signalingUri is built via Uri.parse, which normalizes the host to
      // lowercase (harmless: DNS hostnames are case-insensitive).
      expect(
        config.signalingUri.toString(),
        'wss://sonicrelay-api.hugodotnet.dev/ws/signaling',
      );
    });

    test('derives a ws WebSocket URL from an http server URL', () {
      final config = AppConfig.fromServerUrl('http://localhost:5000');

      expect(config.apiBaseUrl, 'http://localhost:5000');
      expect(config.webSocketBaseUrl, 'ws://localhost:5000');
    });

    test('trims whitespace and trailing slashes', () {
      final config = AppConfig.fromServerUrl('  https://example.com/  ');

      expect(config.apiBaseUrl, 'https://example.com');
      expect(config.webSocketBaseUrl, 'wss://example.com');
    });

    test('defaults to the production server URL', () {
      expect(
        AppConfig.defaultServerUrl,
        'https://sonicRelay-api.hugodotnet.dev',
      );
    });
  });
}
