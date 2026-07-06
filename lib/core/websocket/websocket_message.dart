import 'dart:convert';

/// A raw JSON-object frame exchanged over a [WebSocketClient].
///
/// This type carries no knowledge of any particular message schema; feature
/// layers (e.g. `features/signaling`) map it to their own typed models.
class WebSocketMessage {
  const WebSocketMessage(this.data);

  factory WebSocketMessage.decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return WebSocketMessage(Map<String, Object?>.from(decoded));
    }
    throw const FormatException('WebSocket frame must be a JSON object.');
  }

  final Map<String, Object?> data;

  String encode() => jsonEncode(data);
}
