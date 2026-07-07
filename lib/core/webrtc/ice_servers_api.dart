import 'package:dio/dio.dart';

import 'rtc_ice_server_config.dart';

/// Result of fetching ICE servers from the backend: the server list plus the
/// TTL (seconds) of any short-lived TURN credentials it carries.
class IceServersResult {
  const IceServersResult({required this.config, required this.ttlSeconds});

  final RtcIceServerConfig config;
  final int ttlSeconds;
}

abstract interface class IceServersApi {
  Future<IceServersResult> fetch();
}

class DioIceServersApi implements IceServersApi {
  const DioIceServersApi(this._dio);

  final Dio _dio;

  @override
  Future<IceServersResult> fetch() async {
    final response = await _dio.get<Map<String, Object?>>(
      '/api/webrtc/ice-servers',
    );
    final data = response.data ?? const {};
    final rawServers = data['iceServers'];
    final servers = <RtcIceServer>[];
    if (rawServers is List) {
      for (final entry in rawServers) {
        if (entry is! Map) continue;
        final map = Map<String, Object?>.from(entry);
        final urls = _readUrls(map['urls']);
        if (urls.isEmpty) continue;
        servers.add(
          RtcIceServer(
            urls: urls,
            username: map['username'] as String?,
            credential: map['credential'] as String?,
          ),
        );
      }
    }
    final ttl = data['ttlSeconds'];
    return IceServersResult(
      config: servers.isEmpty
          ? RtcIceServerConfig.defaults()
          : RtcIceServerConfig(servers),
      ttlSeconds: ttl is num ? ttl.toInt() : 3600,
    );
  }

  /// The backend serializes `urls` as a list, but tolerate a bare string too so
  /// a future/looser server shape does not break the viewer.
  static List<String> _readUrls(Object? value) {
    if (value is String) return value.isEmpty ? const [] : [value];
    if (value is List) {
      return value.whereType<String>().where((url) => url.isNotEmpty).toList();
    }
    return const [];
  }
}
