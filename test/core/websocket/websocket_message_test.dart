import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/websocket/websocket_message.dart';

void main() {
  test('decodes a JSON object frame', () {
    final message = WebSocketMessage.decode('{"type":"ping","messageId":"1"}');

    expect(message.data['type'], 'ping');
    expect(message.data['messageId'], '1');
  });

  test('encodes back to the same JSON shape', () {
    const message = WebSocketMessage({'type': 'pong', 'messageId': '2'});

    expect(message.encode(), '{"type":"pong","messageId":"2"}');
  });

  test('throws FormatException for non-object JSON', () {
    expect(() => WebSocketMessage.decode('[1,2,3]'), throwsFormatException);
    expect(() => WebSocketMessage.decode('"just a string"'), throwsFormatException);
  });
}
