import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/webrtc/ice_servers_api.dart';
import 'package:sonic_relay/core/webrtc/ice_servers_repository.dart';
import 'package:sonic_relay/core/webrtc/rtc_ice_server_config.dart';

class _StubIceServersApi implements IceServersApi {
  _StubIceServersApi(this._result);

  IceServersResult _result;
  Object? _error;
  int calls = 0;

  void failWith(Object error) => _error = error;
  set result(IceServersResult value) {
    _result = value;
    _error = null;
  }

  @override
  Future<IceServersResult> fetch() async {
    calls++;
    if (_error != null) throw _error!;
    return _result;
  }
}

IceServersResult _result({
  List<RtcIceServer>? servers,
  required DateTime expiresAt,
}) {
  return IceServersResult(
    config: RtcIceServerConfig(
      servers ??
          const [
            RtcIceServer(
              urls: ['turn:sonicrelay-turn.hugodotnet.dev:3478?transport=udp'],
              username: 'u',
              credential: 'c',
            ),
          ],
    ),
    expiresAt: expiresAt,
  );
}

void main() {
  test('returns the fetched config', () async {
    final now = DateTime.utc(2026);
    final api = _StubIceServersApi(_result(expiresAt: now.add(const Duration(hours: 1))));
    final repo = IceServersRepository(api: api, now: () => now);

    final config = await repo.resolve();

    expect(config.iceServers.single.urls, [
      'turn:sonicrelay-turn.hugodotnet.dev:3478?transport=udp',
    ]);
    expect(api.calls, 1);
  });

  test('caches until 60s before expiresAt', () async {
    var now = DateTime.utc(2026);
    final api = _StubIceServersApi(_result(expiresAt: now.add(const Duration(hours: 1))));
    final repo = IceServersRepository(api: api, now: () => now);

    await repo.resolve();
    now = now.add(const Duration(seconds: 3600 - 60 - 1));
    await repo.resolve();
    expect(api.calls, 1);

    now = now.add(const Duration(seconds: 2));
    await repo.resolve();
    expect(api.calls, 2);
  });

  test(
    'in dev mode, falls back to Google STUN defaults when the fetch fails and no cache exists',
    () async {
      final api = _StubIceServersApi(
        _result(expiresAt: DateTime.utc(2026).add(const Duration(hours: 1))),
      )..failWith(DioException(requestOptions: RequestOptions(path: '/x')));
      final repo = IceServersRepository(
        api: api,
        allowGoogleStunDevFallback: true,
      );

      final config = await repo.resolve();

      expect(config.iceServers.single.urls.first, startsWith('stun:'));
    },
  );

  test(
    'in production mode, does not fall back to Google STUN when the fetch fails and no cache exists',
    () async {
      final api = _StubIceServersApi(
        _result(expiresAt: DateTime.utc(2026).add(const Duration(hours: 1))),
      )..failWith(DioException(requestOptions: RequestOptions(path: '/x')));
      final repo = IceServersRepository(
        api: api,
        allowGoogleStunDevFallback: false,
      );

      final config = await repo.resolve();

      expect(config.iceServers, isEmpty);
    },
  );

  test('returns the last good cache when a later refresh fails, even in production mode', () async {
    var now = DateTime.utc(2026);
    final api = _StubIceServersApi(_result(expiresAt: now.add(const Duration(hours: 1))));
    final repo = IceServersRepository(
      api: api,
      now: () => now,
      allowGoogleStunDevFallback: false,
    );
    await repo.resolve();

    api.failWith(DioException(requestOptions: RequestOptions(path: '/x')));
    now = now.add(const Duration(hours: 2));

    final config = await repo.resolve();
    expect(config.iceServers.single.urls, [
      'turn:sonicrelay-turn.hugodotnet.dev:3478?transport=udp',
    ]);
  });
}
