import 'signaling_message_type.dart';

/// Typed signaling envelope. Used across the app instead of raw dynamic maps.
class SignalingMessage {
  const SignalingMessage({
    required this.type,
    required this.messageId,
    required this.sessionId,
    required this.timestamp,
    this.from,
    this.to,
    this.payload = const {},
    this.rawType,
  });

  final SignalingMessageType type;
  final String messageId;
  final String sessionId;
  final String? from;
  final String? to;
  final DateTime timestamp;
  final Map<String, Object?> payload;

  /// Preserves the original wire value when [type] could not be matched to
  /// a known [SignalingMessageType] (i.e. it is [SignalingMessageType.unknown]).
  final String? rawType;
}
