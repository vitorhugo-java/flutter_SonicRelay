import 'package:dio/dio.dart';

import '../diagnostics/sonic_log.dart';
import 'ice_servers_api.dart';
import 'rtc_ice_server_config.dart';

/// Resolves the ICE server configuration used for a WebRTC negotiation, caching
/// the backend result until shortly before its TURN credentials expire. It
/// never throws: on failure it returns the last good configuration, or the
/// public-STUN defaults, so a negotiation always has servers to work with.
class IceServersRepository {
  IceServersRepository({required IceServersApi api, DateTime Function()? now})
    : _api = api,
      _now = now ?? DateTime.now;

  final IceServersApi _api;
  final DateTime Function() _now;

  RtcIceServerConfig? _cached;
  DateTime _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<RtcIceServerConfig> resolve() async {
    final cached = _cached;
    if (cached != null && _now().isBefore(_expiresAt)) {
      return cached;
    }
    try {
      final result = await _api.fetch();
      // Refresh a minute before the credentials lapse so a renegotiation never
      // starts with a stale TURN username.
      final ttl = result.ttlSeconds - 60;
      _expiresAt = _now().add(
        Duration(seconds: ttl < 30 ? 30 : ttl),
      );
      _cached = result.config;
      return result.config;
    } on DioException catch (error) {
      sonicLog('WebRTC', 'ice-servers fetch failed: ${error.message}');
      return _cached ?? RtcIceServerConfig.defaults();
    } catch (error) {
      sonicLog('WebRTC', 'ice-servers parse failed: $error');
      return _cached ?? RtcIceServerConfig.defaults();
    }
  }
}
