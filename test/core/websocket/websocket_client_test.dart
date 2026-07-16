import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/diagnostics/diagnostic_log.dart';
import 'package:sonic_relay/core/websocket/websocket_client.dart';

DiagnosticLog _testLog() =>
    DiagnosticLog(Directory.systemTemp.createTempSync('sonicrelay_ws_test_').path);

/// A [math.Random] whose [nextDouble] always returns a fixed value, so
/// jitter-dependent tests get a deterministic sample instead of a real draw.
class _FixedRandom implements math.Random {
  _FixedRandom(this._value);
  final double _value;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => _value;

  @override
  int nextInt(int max) => 0;
}

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

  void emitError(Object error) => _controller.addError(error);
}

Timer _instantTimer(Duration delay, void Function() callback) =>
    Timer(Duration.zero, callback);

void main() {
  group('ReconnectPolicy', () {
    test('zero jitter ratio returns the plain backoff delay', () {
      const policy = ReconnectPolicy(jitterRatio: 0);
      expect(
        policy.jitteredDelayForAttempt(0, 1),
        policy.delayForAttempt(0),
      );
    });

    test('jitter never pushes the delay below zero', () {
      const policy = ReconnectPolicy(jitterRatio: 1, maxDelay: Duration(seconds: 1));
      expect(policy.jitteredDelayForAttempt(0, -1), Duration.zero);
    });

    test('jitter is clamped to maxDelay', () {
      const policy = ReconnectPolicy(
        initialDelay: Duration(seconds: 20),
        maxDelay: Duration(seconds: 30),
        jitterRatio: 1,
      );
      expect(policy.jitteredDelayForAttempt(0, 1), const Duration(seconds: 30));
    });
  });

  group('WebSocketClient', () {
    test('connects and emits connecting then connected', () async {
      final connections = <FakeWebSocketConnection>[];
      final client = WebSocketClient(
        diagnosticLog: _testLog(),
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
        diagnosticLog: _testLog(),
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
        diagnosticLog: _testLog(),
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
        diagnosticLog: _testLog(),
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
        diagnosticLog: _testLog(),
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

    test('reconnect delay is jittered per the configured ratio', () async {
      final connections = <FakeWebSocketConnection>[];
      final delays = <Duration>[];
      final client = WebSocketClient(
        diagnosticLog: _testLog(),
        connector: (uri, headers) async {
          final connection = FakeWebSocketConnection();
          connections.add(connection);
          return connection;
        },
        scheduleTimer: (delay, callback) {
          delays.add(delay);
          return Timer(Duration.zero, callback);
        },
        reconnectPolicy: const ReconnectPolicy(jitterRatio: 0.5),
        random: _FixedRandom(1.0),
      );
      addTearDown(client.dispose);

      await client.connect(Uri.parse('wss://example.test/ws'));
      connections.single.emitDone();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Base delay for the first attempt is 1s; a maximal +1 jitter sample
      // scaled by a 0.5 ratio pushes it to 1.5s.
      expect(delays, [const Duration(milliseconds: 1500)]);
    });

    test('reconnect resolves headers again for every attempt', () async {
      final connections = <FakeWebSocketConnection>[];
      final headersSeen = <Map<String, String>>[];
      var callCount = 0;
      final client = WebSocketClient(
        diagnosticLog: _testLog(),
        connector: (uri, headers) async {
          headersSeen.add(headers);
          final connection = FakeWebSocketConnection();
          connections.add(connection);
          return connection;
        },
        scheduleTimer: _instantTimer,
      );
      addTearDown(client.dispose);

      await client.connect(
        Uri.parse('wss://example.test/ws'),
        headers: () {
          callCount++;
          return {'Authorization': 'Bearer token-$callCount'};
        },
      );
      connections.single.emitDone();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(headersSeen, [
        {'Authorization': 'Bearer token-1'},
        {'Authorization': 'Bearer token-2'},
      ]);
    });

    test('disconnect stops reconnect attempts', () async {
      final connections = <FakeWebSocketConnection>[];
      final client = WebSocketClient(
        diagnosticLog: _testLog(),
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

    test('disconnectReasons emits serverClosed when the peer closes the socket', () async {
      final connections = <FakeWebSocketConnection>[];
      final client = WebSocketClient(
        diagnosticLog: _testLog(),
        connector: (uri, headers) async {
          final connection = FakeWebSocketConnection();
          connections.add(connection);
          return connection;
        },
        scheduleTimer: _instantTimer,
      );
      addTearDown(client.dispose);
      final reasons = <WebSocketDisconnectReason>[];
      final sub = client.disconnectReasons.listen(reasons.add);

      await client.connect(Uri.parse('wss://example.test/ws'));
      connections.single.emitDone();
      await Future<void>.delayed(Duration.zero);

      expect(reasons, [WebSocketDisconnectReason.serverClosed]);
      await sub.cancel();
    });

    test('disconnectReasons emits transportError on a stream error', () async {
      final connections = <FakeWebSocketConnection>[];
      final client = WebSocketClient(
        diagnosticLog: _testLog(),
        connector: (uri, headers) async {
          final connection = FakeWebSocketConnection();
          connections.add(connection);
          return connection;
        },
        scheduleTimer: _instantTimer,
      );
      addTearDown(client.dispose);
      final reasons = <WebSocketDisconnectReason>[];
      final sub = client.disconnectReasons.listen(reasons.add);

      await client.connect(Uri.parse('wss://example.test/ws'));
      connections.single.emitError(Exception('boom'));
      await Future<void>.delayed(Duration.zero);

      expect(reasons, [WebSocketDisconnectReason.transportError]);
      await sub.cancel();
    });

    test('disconnectReasons emits connectFailed when the connector throws', () async {
      var attempts = 0;
      final client = WebSocketClient(
        diagnosticLog: _testLog(),
        connector: (uri, headers) async {
          attempts++;
          if (attempts == 1) throw Exception('connect failed');
          return FakeWebSocketConnection();
        },
        scheduleTimer: _instantTimer,
      );
      addTearDown(client.dispose);
      final reasons = <WebSocketDisconnectReason>[];
      final sub = client.disconnectReasons.listen(reasons.add);

      await client.connect(Uri.parse('wss://example.test/ws'));
      await Future<void>.delayed(Duration.zero);

      expect(reasons, [WebSocketDisconnectReason.connectFailed]);
      await sub.cancel();
    });

    test('disconnectReasons emits normal on an explicit disconnect', () async {
      final client = WebSocketClient(
        diagnosticLog: _testLog(),
        connector: (uri, headers) async => FakeWebSocketConnection(),
        scheduleTimer: _instantTimer,
      );
      addTearDown(client.dispose);
      final reasons = <WebSocketDisconnectReason>[];
      final sub = client.disconnectReasons.listen(reasons.add);

      await client.connect(Uri.parse('wss://example.test/ws'));
      await client.disconnect();
      // The broadcast stream delivers via a microtask, so let it flush before
      // asserting — the same pattern other tests in this file use for
      // disconnectReasons/connectionState events.
      await Future<void>.delayed(Duration.zero);

      expect(reasons, [WebSocketDisconnectReason.normal]);
      await sub.cancel();
    });
  });
}
