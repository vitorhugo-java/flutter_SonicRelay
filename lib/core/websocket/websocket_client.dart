import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../diagnostics/sonic_log.dart';
import 'websocket_message.dart';

enum WebSocketConnectionState {
  connecting,
  connected,
  reconnecting,
  disconnected,
}

/// A single open transport connection, abstracted so [WebSocketClient] can
/// be tested without opening a real socket.
abstract interface class WebSocketConnection {
  Stream<dynamic> get stream;

  void add(String data);

  Future<void> close();
}

typedef WebSocketConnector =
    Future<WebSocketConnection> Function(Uri uri, Map<String, String> headers);

/// Produces connection headers (e.g. a bearer token) fresh for each connect
/// attempt, so a token that expires mid-outage is picked up on the next retry
/// instead of retrying forever with a stale, now-rejected header.
typedef WebSocketHeadersProvider = FutureOr<Map<String, String>> Function();

/// Default [WebSocketConnector] backed by `dart:io`'s [WebSocket].
Future<WebSocketConnection> ioWebSocketConnector(
  Uri uri,
  Map<String, String> headers,
) async {
  final socket = await WebSocket.connect(uri.toString(), headers: headers);
  return _IoWebSocketConnection(socket);
}

class _IoWebSocketConnection implements WebSocketConnection {
  _IoWebSocketConnection(this._socket);

  final WebSocket _socket;

  @override
  Stream<dynamic> get stream => _socket;

  @override
  void add(String data) => _socket.add(data);

  @override
  Future<void> close() => _socket.close();
}

/// Exponential backoff with a cap, used between reconnect attempts.
class ReconnectPolicy {
  const ReconnectPolicy({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2.0,
    this.jitterRatio = 0.2,
  });

  final Duration initialDelay;
  final Duration maxDelay;
  final double multiplier;

  /// Fraction of the computed delay randomized in both directions (e.g. 0.2
  /// means +/-20%), so clients dropped by the same outage don't all retry the
  /// API in lockstep. Zero disables jitter.
  final double jitterRatio;

  Duration delayForAttempt(int attempt) {
    final scaledMillis =
        initialDelay.inMilliseconds * math.pow(multiplier, attempt);
    final cappedMillis = scaledMillis.clamp(
      initialDelay.inMilliseconds.toDouble(),
      maxDelay.inMilliseconds.toDouble(),
    );
    return Duration(milliseconds: cappedMillis.round());
  }

  /// [delayForAttempt] jittered by +/-[jitterRatio], using [jitterSample] — a
  /// value in [-1, 1] — as the random draw. Clamped to [0, maxDelay].
  Duration jitteredDelayForAttempt(int attempt, double jitterSample) {
    final base = delayForAttempt(attempt);
    final ratio = jitterRatio.clamp(0.0, 1.0);
    if (ratio <= 0) return base;
    final fraction = ratio * jitterSample.clamp(-1.0, 1.0);
    final jitteredMillis = (base.inMilliseconds * (1 + fraction)).clamp(
      0.0,
      maxDelay.inMilliseconds.toDouble(),
    );
    return Duration(milliseconds: jitteredMillis.round());
  }
}

/// Reconnecting JSON-over-WebSocket transport.
///
/// This class carries no domain knowledge of the messages it ferries; see
/// `features/signaling` for message semantics and routing.
class WebSocketClient {
  WebSocketClient({
    required WebSocketConnector connector,
    ReconnectPolicy reconnectPolicy = const ReconnectPolicy(),
    Timer Function(Duration delay, void Function() callback)? scheduleTimer,
    math.Random? random,
  }) : _connector = connector,
       _reconnectPolicy = reconnectPolicy,
       _scheduleTimer = scheduleTimer ?? Timer.new,
       _random = random ?? math.Random();

  final WebSocketConnector _connector;
  final ReconnectPolicy _reconnectPolicy;
  final Timer Function(Duration delay, void Function() callback)
  _scheduleTimer;
  final math.Random _random;

  final _stateController =
      StreamController<WebSocketConnectionState>.broadcast();
  final _messageController = StreamController<WebSocketMessage>.broadcast();

  Stream<WebSocketConnectionState> get connectionState =>
      _stateController.stream;

  Stream<WebSocketMessage> get messages => _messageController.stream;

  WebSocketConnection? _connection;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _stopped = true;
  Uri? _uri;
  WebSocketHeadersProvider _headersProvider = _emptyHeaders;

  static Map<String, String> _emptyHeaders() => const {};

  Future<void> connect(Uri uri, {WebSocketHeadersProvider? headers}) async {
    _stopped = false;
    _uri = uri;
    _headersProvider = headers ?? _emptyHeaders;
    _attempt = 0;
    _reconnectTimer?.cancel();
    await _attemptConnect();
  }

  Future<void> _attemptConnect() async {
    if (_stopped) return;
    if (_attempt == 0) {
      _stateController.add(WebSocketConnectionState.connecting);
    }
    try {
      sonicLog('WebSocket', 'connecting to $_uri (attempt $_attempt)');
      // Resolved fresh on every attempt (not just the first) so a token that
      // expired during the outage is refreshed before the next retry instead
      // of retrying forever with a now-rejected header.
      final headers = await _headersProvider();
      final connection = await _connector(_uri!, headers);
      if (_stopped) {
        await connection.close();
        return;
      }
      _connection = connection;
      _attempt = 0;
      sonicLog('WebSocket', 'connected to $_uri');
      _stateController.add(WebSocketConnectionState.connected);
      _subscription = connection.stream.listen(
        (dynamic data) {
          if (data is String) {
            _messageController.add(WebSocketMessage.decode(data));
          }
        },
        onDone: () {
          sonicLog('WebSocket', 'socket closed by peer');
          _handleDisconnect();
        },
        onError: (Object error) {
          sonicLog('WebSocket', 'socket error: $error');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (error) {
      sonicLog('WebSocket', 'connect failed: $error');
      _scheduleReconnect();
    }
  }

  void _handleDisconnect() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _connection = null;
    if (_stopped) {
      _stateController.add(WebSocketConnectionState.disconnected);
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_stopped) return;
    final jitterSample = _random.nextDouble() * 2 - 1;
    final delay = _reconnectPolicy.jitteredDelayForAttempt(
      _attempt,
      jitterSample,
    );
    _attempt++;
    _stateController.add(WebSocketConnectionState.reconnecting);
    _reconnectTimer = _scheduleTimer(delay, () {
      unawaited(_attemptConnect());
    });
  }

  /// Sends a raw text frame. Silently dropped while disconnected.
  void send(String data) => _connection?.add(data);

  /// Closes the connection and stops all reconnect attempts.
  Future<void> disconnect() async {
    _stopped = true;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _connection?.close();
    _connection = null;
    _stateController.add(WebSocketConnectionState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
    await _messageController.close();
  }
}
