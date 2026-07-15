import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/storage/secure_token_storage.dart';
import 'package:sonic_relay/core/websocket/websocket_client.dart';
import 'package:sonic_relay/features/auth/domain/auth_session.dart';
import 'package:sonic_relay/features/sessions/domain/stream_session.dart';
import 'package:sonic_relay/features/signaling/data/signaling_client.dart';
import 'package:sonic_relay/features/signaling/domain/signaling_message_type.dart';

class FakeWebSocketConnection implements WebSocketConnection {
  final _controller = StreamController<dynamic>.broadcast();
  final List<String> sent = [];
  bool closed = false;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void add(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    await _controller.close();
  }

  void emit(String data) => _controller.add(data);
}

class FakeTokenStorage implements TokenStorage {
  FakeTokenStorage(this._session);
  AuthSession? _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}

Timer _instantTimer(Duration delay, void Function() callback) =>
    Timer(Duration.zero, callback);

Map<String, Object?> _decode(String raw) =>
    jsonDecode(raw) as Map<String, Object?>;

void main() {
  late List<Uri> requestedUris;
  late List<Map<String, String>> requestedHeaders;
  late FakeWebSocketConnection connection;
  late SignalingClient signalingClient;
  late StreamSession session;

  setUp(() {
    requestedUris = [];
    requestedHeaders = [];
    final webSocketClient = WebSocketClient(
      connector: (uri, headers) async {
        requestedUris.add(uri);
        requestedHeaders.add(headers);
        connection = FakeWebSocketConnection();
        return connection;
      },
      scheduleTimer: _instantTimer,
    );
    signalingClient = SignalingClient(
      webSocketClient: webSocketClient,
      tokenStorage: FakeTokenStorage(
        const AuthSession(
          accessToken: 'token-abc',
          refreshToken: 'refresh',
          expiresIn: 3600,
          tokenType: 'Bearer',
        ),
      ),
    );
    session = StreamSession(
      sessionId: 'session-1',
      signalingUrl: Uri.parse(
        'wss://stream.example/ws/signaling?sessionId=session-1',
      ),
    );
  });

  tearDown(() => signalingClient.dispose());

  test('connects with sessionId/deviceId query params and bearer auth', () async {
    await signalingClient.connect(session: session, deviceId: 'device-9');
    await Future<void>.delayed(Duration.zero);

    expect(requestedUris, hasLength(1));
    final uri = requestedUris.single;
    expect(uri.queryParameters['sessionId'], 'session-1');
    expect(uri.queryParameters['deviceId'], 'device-9');
    expect(requestedHeaders.single['Authorization'], 'Bearer token-abc');
  });

  test('does not auto-send viewer.ready on connect', () async {
    // `viewer.ready` is a routed message the backend rejects without a `to`
    // recipient. It is now sent by the WebRTC receiver in reply to
    // `publisher.ready`, not automatically on socket open.
    await signalingClient.connect(session: session, deviceId: 'device-9');
    await Future<void>.delayed(Duration.zero);

    expect(connection.sent, isEmpty);
  });

  test('sends a targeted message via send()', () async {
    await signalingClient.connect(session: session, deviceId: 'device-9');
    await Future<void>.delayed(Duration.zero);

    signalingClient.send(
      SignalingMessageType.viewerReady,
      const {},
      to: 'publisher-7',
    );

    expect(connection.sent, hasLength(1));
    final sentMessage = _decode(connection.sent.single);
    expect(sentMessage['type'], 'viewer.ready');
    expect(sentMessage['sessionId'], 'session-1');
    expect(sentMessage['to'], 'publisher-7');
  });

  test('replies with pong when the server sends a ping', () async {
    await signalingClient.connect(session: session, deviceId: 'device-9');
    await Future<void>.delayed(Duration.zero);

    connection.emit(
      jsonEncode({
        'type': 'ping',
        'messageId': 'srv-1',
        'sessionId': 'session-1',
        'from': 'server',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'payload': {},
      }),
    );
    await Future<void>.delayed(Duration.zero);

    expect(connection.sent, hasLength(1));
    final pong = _decode(connection.sent.single);
    expect(pong['type'], 'pong');
    expect(pong['to'], 'server');
  });

  test('session.ended closes the connection and stops reconnecting', () async {
    await signalingClient.connect(session: session, deviceId: 'device-9');
    await Future<void>.delayed(Duration.zero);

    final states = <SignalingConnectionState>[];
    final sub = signalingClient.connectionState.listen(states.add);

    connection.emit(
      jsonEncode({
        'type': 'session.ended',
        'messageId': 'srv-2',
        'sessionId': 'session-1',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'payload': {},
      }),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(states, contains(SignalingConnectionState.ended));
    expect(states.last, SignalingConnectionState.disconnected);
    expect(connection.closed, isTrue);

    await sub.cancel();
  });

  test(
    'reconnect re-reads the token so a rotated token is picked up',
    () async {
      final tokenStorage = FakeTokenStorage(
        const AuthSession(
          accessToken: 'token-abc',
          refreshToken: 'refresh',
          expiresIn: 3600,
          tokenType: 'Bearer',
        ),
      );
      final headersSeen = <Map<String, String>>[];
      late FakeWebSocketConnection localConnection;
      final webSocketClient = WebSocketClient(
        connector: (uri, headers) async {
          headersSeen.add(headers);
          localConnection = FakeWebSocketConnection();
          return localConnection;
        },
        scheduleTimer: _instantTimer,
      );
      final client = SignalingClient(
        webSocketClient: webSocketClient,
        tokenStorage: tokenStorage,
      );
      addTearDown(client.dispose);

      await client.connect(session: session, deviceId: 'device-9');
      await Future<void>.delayed(Duration.zero);

      // The token rotates mid-outage (e.g. a background refresh completed).
      await tokenStorage.write(
        const AuthSession(
          accessToken: 'token-xyz',
          refreshToken: 'refresh-2',
          expiresIn: 3600,
          tokenType: 'Bearer',
        ),
      );
      await localConnection.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(headersSeen, [
        {'Authorization': 'Bearer token-abc'},
        {'Authorization': 'Bearer token-xyz'},
      ]);
    },
  );

  test('forwards unknown message types without throwing', () async {
    await signalingClient.connect(session: session, deviceId: 'device-9');
    await Future<void>.delayed(Duration.zero);

    final messageFuture = signalingClient.messages.first;
    connection.emit(
      jsonEncode({
        'type': 'future.message',
        'messageId': 'srv-3',
        'sessionId': 'session-1',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'payload': {'x': 1},
      }),
    );

    final message = await messageFuture;
    expect(message.type, SignalingMessageType.unknown);
    expect(message.rawType, 'future.message');
  });
}
