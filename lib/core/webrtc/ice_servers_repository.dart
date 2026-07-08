import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../diagnostics/sonic_log.dart';
import 'ice_servers_api.dart';
import 'rtc_ice_server_config.dart';

/// Resolves the ICE server configuration used for a WebRTC negotiation,
/// caching the backend result until shortly before its TURN credentials
/// expire. It never throws: on failure it returns the last good
/// configuration. If there is no cache yet, it falls back to the public-STUN
/// [RtcIceServerConfig.defaults] only when [allowGoogleStunDevFallback] is
/// true (debug builds by default) — production builds instead get an empty
/// ICE server list rather than silently depending on Google's public STUN
/// server, per the "no production code path relies only on Google STUN"
/// requirement.
class IceServersRepository {
  IceServersRepository({
    required IceServersApi api,
    DateTime Function()? now,
    bool? allowGoogleStunDevFallback,
  }) : _api = api,
       _now = now ?? DateTime.now,
       _allowGoogleStunDevFallback =
           allowGoogleStunDevFallback ?? kDebugMode;

  final IceServersApi _api;
  final DateTime Function() _now;
  final bool _allowGoogleStunDevFallback;

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
      final marginSeconds = result.expiresAt.difference(_now()).inSeconds - 60;
      _expiresAt = _now().add(
        Duration(seconds: marginSeconds < 30 ? 30 : marginSeconds),
      );
      _cached = result.config;
      return result.config;
    } on DioException catch (error) {
      sonicLog('WebRTC', 'ice-servers fetch failed: ${error.message}');
      return _fallback();
    } catch (error) {
      sonicLog('WebRTC', 'ice-servers parse failed: $error');
      return _fallback();
    }
  }

  RtcIceServerConfig _fallback() {
    final cached = _cached;
    if (cached != null) return cached;
    if (_allowGoogleStunDevFallback) return RtcIceServerConfig.defaults();
    return const RtcIceServerConfig([]);
  }
}
