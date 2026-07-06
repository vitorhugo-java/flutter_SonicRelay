import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/webrtc/rtc_ice_server_config.dart';

void main() {
  test('defaults expose a single public STUN server and no credentials', () {
    final config = RtcIceServerConfig.defaults();
    final map = config.toConfiguration();

    expect(map['sdpSemantics'], 'unified-plan');
    final servers = map['iceServers'] as List;
    expect(servers, hasLength(1));
    expect((servers.single as Map)['urls'], ['stun:stun.l.google.com:19302']);
    expect((servers.single as Map).containsKey('username'), isFalse);
    expect((servers.single as Map).containsKey('credential'), isFalse);
  });

  test('custom servers including TURN credentials serialize to configuration', () {
    const config = RtcIceServerConfig([
      RtcIceServer(urls: ['stun:stun.example:3478']),
      RtcIceServer(
        urls: ['turn:turn.example:3478'],
        username: 'user',
        credential: 'secret',
      ),
    ]);

    final servers = config.toConfiguration()['iceServers'] as List;
    expect(servers, hasLength(2));
    final turn = servers[1] as Map;
    expect(turn['urls'], ['turn:turn.example:3478']);
    expect(turn['username'], 'user');
    expect(turn['credential'], 'secret');
  });
}
