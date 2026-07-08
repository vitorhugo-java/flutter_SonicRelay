import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/webrtc/rtc_ice_server_config.dart';

void main() {
  test('defaults expose the dev-only public STUN fallback and no credentials', () {
    final config = RtcIceServerConfig.defaults();
    final map = config.toConfiguration();

    expect(map['sdpSemantics'], 'unified-plan');
    final servers = map['iceServers'] as List;
    expect(servers, hasLength(1));
    expect((servers.single as Map)['urls'], ['stun:stun1.google.com:19302']);
    expect((servers.single as Map).containsKey('username'), isFalse);
    expect((servers.single as Map).containsKey('credential'), isFalse);
  });

  test('defaults to allowing direct (non-relay) ICE', () {
    expect(RtcIceServerConfig.defaults().toConfiguration()['iceTransportPolicy'], 'all');
  });

  test('withRelay forces relay-only ICE while preserving the servers', () {
    final base = RtcIceServerConfig.defaults();
    final relayed = base.withRelay(true);

    expect(relayed.forceRelay, isTrue);
    expect(relayed.toConfiguration()['iceTransportPolicy'], 'relay');
    // Server list is unchanged by the relay override.
    expect(relayed.iceServers, base.iceServers);
    // The original is untouched (immutable copy).
    expect(base.toConfiguration()['iceTransportPolicy'], 'all');
  });

  test('custom servers including TURN credentials serialize to configuration', () {
    const config = RtcIceServerConfig([
      RtcIceServer(urls: ['stun:sonicrelay-turn.hugodotnet.dev:3478']),
      RtcIceServer(
        urls: [
          'turn:sonicrelay-turn.hugodotnet.dev:3478?transport=udp',
          'turn:sonicrelay-turn.hugodotnet.dev:3478?transport=tcp',
          'turns:sonicrelay-turn.hugodotnet.dev:5349?transport=tcp',
        ],
        username: '1735689600:user-1',
        credential: 'base64-hmac-credential',
      ),
    ]);

    final servers = config.toConfiguration()['iceServers'] as List;
    expect(servers, hasLength(2));
    final turn = servers[1] as Map;
    expect(turn['urls'], [
      'turn:sonicrelay-turn.hugodotnet.dev:3478?transport=udp',
      'turn:sonicrelay-turn.hugodotnet.dev:3478?transport=tcp',
      'turns:sonicrelay-turn.hugodotnet.dev:5349?transport=tcp',
    ]);
    expect(turn['username'], '1735689600:user-1');
    expect(turn['credential'], 'base64-hmac-credential');
  });

  test('force relay mode default is "all" unless explicitly enabled', () {
    const config = RtcIceServerConfig([
      RtcIceServer(urls: ['stun:sonicrelay-turn.hugodotnet.dev:3478']),
    ]);

    expect(config.forceRelay, isFalse);
    expect(config.toConfiguration()['iceTransportPolicy'], 'all');
    expect(config.withRelay(true).toConfiguration()['iceTransportPolicy'], 'relay');
  });
}
