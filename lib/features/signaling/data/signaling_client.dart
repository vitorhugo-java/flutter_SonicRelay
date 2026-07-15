import 'dart:async';
import 'dart:math';

import '../../../core/diagnostics/sonic_log.dart';
import '../../../core/storage/secure_token_storage.dart';
import '../../../core/websocket/websocket_client.dart';
import '../../../core/websocket/websocket_message.dart';
import '../../sessions/domain/stream_session.dart';
import '../domain/signaling_message.dart';
import '../domain/signaling_message_type.dart';
import 'signaling_message_mapper.dart';

enum SignalingConnectionState {
  connecting,
  connected,
  reconnecting,
  ended,
  disconnected,
}

/// Authenticated WebSocket signaling transport for a joined [StreamSession].
///
/// Owns the low-level [WebSocketClient] lifecycle: connecting with the
/// current access token, announcing readiness, replying to server pings,
/// routing typed messages, and closing/stopping reconnects when the
/// session ends or the viewer leaves.
class SignalingClient {
  SignalingClient({
    required WebSocketClient webSocketClient,
    required TokenStorage tokenStorage,
    SignalingMessageMapper mapper = const SignalingMessageMapper(),
    Random? random,
  }) : _webSocketClient = webSocketClient,
       _tokenStorage = tokenStorage,
       _mapper = mapper,
       _random = random ?? Random() {
    _connectionSubscription = _webSocketClient.connectionState.listen(
      _handleTransportState,
    );
    _messageSubscription = _webSocketClient.messages.listen(_handleRawMessage);
  }

  final WebSocketClient _webSocketClient;
  final TokenStorage _tokenStorage;
  final SignalingMessageMapper _mapper;
  final Random _random;

  final _connectionStateController =
      StreamController<SignalingConnectionState>.broadcast();
  final _messageController = StreamController<SignalingMessage>.broadcast();

  late final StreamSubscription<WebSocketConnectionState>
  _connectionSubscription;
  late final StreamSubscription<WebSocketMessage> _messageSubscription;

  StreamSession? _session;
  String? _deviceId;
  bool _leaving = false;

  Stream<SignalingConnectionState> get connectionState =>
      _connectionStateController.stream;

  Stream<SignalingMessage> get messages => _messageController.stream;

  /// Connects to [session.signalingUrl] with [sessionId] and [deviceId] as
  /// query parameters and the current access token as a bearer header.
  Future<void> connect({
    required StreamSession session,
    required String deviceId,
  }) async {
    _session = session;
    _deviceId = deviceId;
    _leaving = false;

    final uri = _buildUri(session.signalingUrl, session.sessionId, deviceId);
    sonicLog(
      'Signaling',
      'connect sessionId=${session.sessionId} deviceId=$deviceId uri=$uri',
    );
    // Read fresh on every (re)connect attempt, not just this initial one, so
    // a token that expires mid-outage is picked up before the next retry
    // instead of retrying forever with a stale, now-rejected token.
    await _webSocketClient.connect(uri, headers: _resolveHeaders);
  }

  Future<Map<String, String>> _resolveHeaders() async {
    final authSession = await _tokenStorage.read();
    sonicLog('Signaling', 'resolved auth header hasToken=${authSession != null}');
    return <String, String>{
      if (authSession != null)
        'Authorization': '${authSession.tokenType} ${authSession.accessToken}',
    };
  }

  Uri _buildUri(Uri base, String sessionId, String deviceId) {
    final params = Map<String, String>.from(base.queryParameters);
    params['sessionId'] = sessionId;
    params['deviceId'] = deviceId;
    return base.replace(queryParameters: params);
  }

  void _handleTransportState(WebSocketConnectionState state) {
    switch (state) {
      case WebSocketConnectionState.connecting:
        _connectionStateController.add(SignalingConnectionState.connecting);
      case WebSocketConnectionState.connected:
        _connectionStateController.add(SignalingConnectionState.connected);
      case WebSocketConnectionState.reconnecting:
        _connectionStateController.add(SignalingConnectionState.reconnecting);
      case WebSocketConnectionState.disconnected:
        _connectionStateController.add(SignalingConnectionState.disconnected);
    }
  }

  void _handleRawMessage(WebSocketMessage raw) {
    final message = _mapper.fromWebSocketMessage(raw);
    sonicLog(
      'Signaling',
      'recv type=${message.type.wireValue} from=${message.from} '
          'to=${message.to}',
    );
    _messageController.add(message);

    switch (message.type) {
      case SignalingMessageType.ping:
        _sendPong(message);
      case SignalingMessageType.sessionEnded:
        _connectionStateController.add(SignalingConnectionState.ended);
        unawaited(leave());
      default:
        break;
    }
  }

  /// Sends a signaling [type] with [payload] over the current session. Used by
  /// the WebRTC layer to forward `viewer.ready`, `webrtc.answer` and local
  /// `webrtc.ice_candidate` messages, each addressed to a publisher participant.
  /// No-op if there is no active session.
  void send(SignalingMessageType type, Map<String, Object?> payload, {String? to}) =>
      _send(type, payload, to: to);

  void _sendPong(SignalingMessage ping) =>
      _send(SignalingMessageType.pong, const {}, to: ping.from);

  void _send(SignalingMessageType type, Map<String, Object?> payload, {String? to}) {
    final session = _session;
    if (session == null) return;
    sonicLog('Signaling', 'send type=${type.wireValue} to=$to');
    final message = SignalingMessage(
      type: type,
      messageId: _generateMessageId(),
      sessionId: session.sessionId,
      from: _deviceId,
      to: to,
      timestamp: DateTime.now().toUtc(),
      payload: payload,
    );
    _webSocketClient.send(_mapper.toWebSocketMessage(message).encode());
  }

  String _generateMessageId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  /// Closes the socket and stops reconnect attempts. Call when the viewer
  /// leaves the session or the server signals it has ended.
  Future<void> leave() async {
    sonicLog('Signaling', 'leave sessionId=${_session?.sessionId}');
    _leaving = true;
    await _webSocketClient.disconnect();
  }

  bool get isLeaving => _leaving;

  Future<void> dispose() async {
    _leaving = true;
    await _connectionSubscription.cancel();
    await _messageSubscription.cancel();
    await _webSocketClient.dispose();
    await _connectionStateController.close();
    await _messageController.close();
  }
}
