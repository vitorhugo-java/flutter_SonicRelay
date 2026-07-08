import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/webrtc/ice_servers_api.dart';

class _CallbackAdapter implements HttpClientAdapter {
  _CallbackAdapter(this.callback);
  final ResponseBody Function(RequestOptions options) callback;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => callback(options);
  @override
  void close({bool force = false}) {}
}

Dio _dioReturning(Map<String, Object?> body) {
  final dio = Dio(BaseOptions(baseUrl: 'https://sonicrelay-api.hugodotnet.dev'));
  dio.httpClientAdapter = _CallbackAdapter(
    (options) => ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    ),
  );
  return dio;
}

void main() {
  test('parses stun and turn entries with username and credential', () async {
    final api = DioIceServersApi(
      _dioReturning({
        'iceServers': [
          {
            'urls': ['stun:sonicrelay-turn.hugodotnet.dev:3478'],
          },
          {
            'urls': [
              'turn:sonicrelay-turn.hugodotnet.dev:3478?transport=udp',
              'turn:sonicrelay-turn.hugodotnet.dev:3478?transport=tcp',
              'turns:sonicrelay-turn.hugodotnet.dev:5349?transport=tcp',
            ],
            'username': '1735689600:user-1',
            'credential': 'base64-hmac-credential',
          },
        ],
        'iceTransportPolicy': 'all',
        'expiresAt': '2026-07-08T13:00:00Z',
      }),
    );

    final result = await api.fetch();

    expect(result.config.iceServers, hasLength(2));
    final stun = result.config.iceServers[0];
    expect(stun.urls, ['stun:sonicrelay-turn.hugodotnet.dev:3478']);
    expect(stun.username, isNull);
    expect(stun.credential, isNull);

    final turn = result.config.iceServers[1];
    expect(turn.urls, [
      'turn:sonicrelay-turn.hugodotnet.dev:3478?transport=udp',
      'turn:sonicrelay-turn.hugodotnet.dev:3478?transport=tcp',
      'turns:sonicrelay-turn.hugodotnet.dev:5349?transport=tcp',
    ]);
    expect(turn.username, '1735689600:user-1');
    expect(turn.credential, 'base64-hmac-credential');

    expect(result.expiresAt, DateTime.utc(2026, 7, 8, 13));
  });

  test('an empty backend iceServers list is returned as-is, not replaced with dev defaults', () async {
    final api = DioIceServersApi(
      _dioReturning({
        'iceServers': <Object?>[],
        'iceTransportPolicy': 'all',
        'expiresAt': '2026-07-08T13:00:00Z',
      }),
    );

    final result = await api.fetch();

    expect(result.config.iceServers, isEmpty);
  });

  test('falls back to a default TTL when expiresAt is missing or malformed', () async {
    final api = DioIceServersApi(
      _dioReturning({'iceServers': <Object?>[], 'iceTransportPolicy': 'all'}),
    );

    final before = DateTime.now().toUtc();
    final result = await api.fetch();

    expect(result.expiresAt.isAfter(before), isTrue);
  });
}
