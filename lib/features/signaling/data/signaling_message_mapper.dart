import '../../../core/websocket/websocket_message.dart';
import '../domain/signaling_message.dart';
import '../domain/signaling_message_type.dart';

/// Converts between the transport-level [WebSocketMessage] and the typed
/// [SignalingMessage] domain model.
class SignalingMessageMapper {
  const SignalingMessageMapper();

  SignalingMessage fromWebSocketMessage(WebSocketMessage message) {
    final json = message.data;
    final wireType = json['type'];
    final type = wireType is String
        ? SignalingMessageType.fromWireValue(wireType)
        : SignalingMessageType.unknown;
    final payload = json['payload'];
    final timestamp = json['timestamp'];

    return SignalingMessage(
      type: type,
      messageId: json['messageId'] as String? ?? '',
      sessionId: json['sessionId'] as String? ?? '',
      from: json['from'] as String?,
      to: json['to'] as String?,
      timestamp:
          (timestamp is String ? DateTime.tryParse(timestamp) : null) ??
          DateTime.now().toUtc(),
      payload: payload is Map ? Map<String, Object?>.from(payload) : const {},
      rawType: type == SignalingMessageType.unknown && wireType is String
          ? wireType
          : null,
    );
  }

  WebSocketMessage toWebSocketMessage(SignalingMessage message) {
    return WebSocketMessage({
      'type': message.rawType ?? message.type.wireValue,
      'messageId': message.messageId,
      'sessionId': message.sessionId,
      if (message.from != null) 'from': message.from,
      if (message.to != null) 'to': message.to,
      'timestamp': message.timestamp.toIso8601String(),
      'payload': message.payload,
    });
  }
}
