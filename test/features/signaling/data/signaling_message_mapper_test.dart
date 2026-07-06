import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/websocket/websocket_message.dart';
import 'package:sonic_relay/features/signaling/data/signaling_message_mapper.dart';
import 'package:sonic_relay/features/signaling/domain/signaling_message.dart';
import 'package:sonic_relay/features/signaling/domain/signaling_message_type.dart';

void main() {
  const mapper = SignalingMessageMapper();

  test('deserializes a known envelope', () {
    final raw = WebSocketMessage.decode('''
    {
      "type": "webrtc.offer",
      "messageId": "msg-1",
      "sessionId": "session-1",
      "from": "publisher-1",
      "to": "viewer-1",
      "timestamp": "2026-07-03T14:00:00-03:00",
      "payload": {"sdp": "..."}
    }
    ''');

    final message = mapper.fromWebSocketMessage(raw);

    expect(message.type, SignalingMessageType.webrtcOffer);
    expect(message.messageId, 'msg-1');
    expect(message.sessionId, 'session-1');
    expect(message.from, 'publisher-1');
    expect(message.to, 'viewer-1');
    expect(message.payload['sdp'], '...');
    expect(message.timestamp.toUtc().hour, 17);
  });

  test('round-trips serialization for every known message type', () {
    for (final type in SignalingMessageType.values) {
      if (type == SignalingMessageType.unknown) continue;
      final message = SignalingMessage(
        type: type,
        messageId: 'msg-id',
        sessionId: 'session-1',
        from: 'device-a',
        to: 'device-b',
        timestamp: DateTime.utc(2026, 7, 3, 14),
        payload: const {'foo': 'bar'},
      );

      final encoded = mapper.toWebSocketMessage(message);
      final decoded = mapper.fromWebSocketMessage(encoded);

      expect(decoded.type, type, reason: 'failed for $type');
      expect(decoded.messageId, 'msg-id');
      expect(decoded.sessionId, 'session-1');
      expect(decoded.payload['foo'], 'bar');
    }
  });

  test('maps an unrecognized type to unknown without throwing', () {
    final raw = WebSocketMessage.decode(
      '{"type":"some.future.type","messageId":"m","sessionId":"s","timestamp":"2026-07-03T14:00:00Z","payload":{}}',
    );

    final message = mapper.fromWebSocketMessage(raw);

    expect(message.type, SignalingMessageType.unknown);
    expect(message.rawType, 'some.future.type');
  });

  test('falls back to empty sessionId/messageId and now() for malformed frames', () {
    final raw = WebSocketMessage.decode('{"type":"ping"}');

    final message = mapper.fromWebSocketMessage(raw);

    expect(message.type, SignalingMessageType.ping);
    expect(message.messageId, '');
    expect(message.sessionId, '');
    expect(message.payload, isEmpty);
  });
}
