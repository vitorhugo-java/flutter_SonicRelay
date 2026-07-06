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
  });

  final Duration initialDelay;
  final Duration maxDelay;
  final double multiplier;

  Duration delayForAttempt(int attempt) {
    final scaledMillis =
        initialDelay.inMilliseconds * math.pow(multiplier, attempt);
    final cappedMillis = scaledMillis.clamp(
      initialDelay.inMilliseconds.toDouble(),
      maxDelay.inMilliseconds.toDouble(),
    );
    return Duration(milliseconds: cappedMillis.round());
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
  }) : _connector = connector,
       _reconnectPolicy = reconnectPolicy,
       _scheduleTimer = scheduleTimer ?? Timer.new;

  final WebSocketConnector _connector;
  final ReconnectPolicy _reconnectPolicy;
  final Timer Function(Duration delay, void Function() callback)
  _scheduleTimer;

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
  Map<String, String> _headers = const {};

  Future<void> connect(Uri uri, {Map<String, String> headers = const {}}) async {
    _stopped = false;
    _uri = uri;
    _headers = headers;
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
      final connection = await _connector(_uri!, _headers);
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
    final delay = _reconnectPolicy.delayForAttempt(_attempt);
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
