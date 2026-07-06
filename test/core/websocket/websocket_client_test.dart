import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/websocket/websocket_client.dart';

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

  void emitDone() => _controller.close();
}

Timer _instantTimer(Duration delay, void Function() callback) =>
    Timer(Duration.zero, callback);

void main() {
  group('WebSocketClient', () {
    test('connects and emits connecting then connected', () async {
      final connections = <FakeWebSocketConnection>[];
      final client = WebSocketClient(
        connector: (uri, headers) async {
          final connection = FakeWebSocketConnection();
          connections.add(connection);
          return connection;
        },
        scheduleTimer: _instantTimer,
      );
      addTearDown(client.dispose);

      final states = <WebSocketConnectionState>[];
      final sub = client.connectionState.listen(states.add);

      await client.connect(Uri.parse('wss://example.test/ws'));
      await Future<void>.delayed(Duration.zero);

      expect(states, [
        WebSocketConnectionState.connecting,
        WebSocketConnectionState.connected,
      ]);
      expect(connections, hasLength(1));
      await sub.cancel();
    });

    test('forwards decoded messages from the connection', () async {
      late FakeWebSocketConnection connection;
      final client = WebSocketClient(
        connector: (uri, headers) async {
          connection = FakeWebSocketConnection();
          return connection;
        },
        scheduleTimer: _instantTimer,
      );
      addTearDown(client.dispose);

      await client.connect(Uri.parse('wss://example.test/ws'));

      final messageFuture = client.messages.first;
      connection.emit('{"type":"ping","messageId":"1"}');
      final message = await messageFuture;

      expect(message.data['type'], 'ping');
    });

    test('send forwards raw text to the active connection', () async {
      late FakeWebSocketConnection connection;
      final client = WebSocketClient(
        connector: (uri, headers) async {
          connection = FakeWebSocketConnection();
          return connection;
        },
        scheduleTimer: _instantTimer,
      );
      addTearDown(client.dispose);

      await client.connect(Uri.parse('wss://example.test/ws'));
      client.send('hello');

      expect(connection.sent, ['hello']);
    });

    test('reconnects with backoff after the connection drops', () async {
      final connections = <FakeWebSocketConnection>[];
      final client = WebSocketClient(
        connector: (uri, headers) async {
          final connection = FakeWebSocketConnection();
          connections.add(connection);
          return connection;
        },
        scheduleTimer: _instantTimer,
      );
      addTearDown(client.dispose);

      final states = <WebSocketConnectionState>[];
      final sub = client.connectionState.listen(states.add);

      await client.connect(Uri.parse('wss://example.test/ws'));
      connections.single.emitDone();

      // Allow the disconnect handler, scheduled reconnect timer, and the
      // resulting connect attempt to run.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(connections, hasLength(2));
      expect(states, [
        WebSocketConnectionState.connecting,
        WebSocketConnectionState.connected,
        WebSocketConnectionState.reconnecting,
        WebSocketConnectionState.connected,
      ]);
      await sub.cancel();
    });

    test('retries connector failures until it succeeds', () async {
      var attempts = 0;
      final connections = <FakeWebSocketConnection>[];
      final client = WebSocketClient(
        connector: (uri, headers) async {
          attempts++;
          if (attempts < 3) {
            throw Exception('connect failed');
          }
          final connection = FakeWebSocketConnection();
          connections.add(connection);
          return connection;
        },
        scheduleTimer: _instantTimer,
      );
      addTearDown(client.dispose);

      final connectedFuture = client.connectionState.firstWhere(
        (state) => state == WebSocketConnectionState.connected,
      );
      await client.connect(Uri.parse('wss://example.test/ws'));
      await connectedFuture;

      expect(attempts, 3);
      expect(connections, hasLength(1));
    });

    test('disconnect stops reconnect attempts', () async {
      final connections = <FakeWebSocketConnection>[];
      final client = WebSocketClient(
        connector: (uri, headers) async {
          final connection = FakeWebSocketConnection();
          connections.add(connection);
          return connection;
        },
        scheduleTimer: _instantTimer,
      );
      addTearDown(client.dispose);

      await client.connect(Uri.parse('wss://example.test/ws'));
      await client.disconnect();

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(connections, hasLength(1));
    });
  });
}
