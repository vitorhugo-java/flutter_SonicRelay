import 'package:dio/dio.dart';

import 'rtc_ice_server_config.dart';

/// Result of fetching ICE servers from the backend: the server list plus
/// when its (possibly time-limited TURN) credentials expire.
class IceServersResult {
  const IceServersResult({required this.config, required this.expiresAt});

  final RtcIceServerConfig config;
  final DateTime expiresAt;
}

abstract interface class IceServersApi {
  Future<IceServersResult> fetch();
}

class DioIceServersApi implements IceServersApi {
  const DioIceServersApi(this._dio);

  final Dio _dio;

  /// Assumed remaining lifetime when the backend omits `expiresAt`, so a
  /// malformed response still expires and gets refreshed rather than being
  /// cached forever.
  static const _defaultTtl = Duration(hours: 1);

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
    // An empty (or missing) list is a valid, authoritative backend response
    // (e.g. TURN not configured and the Google STUN dev fallback disabled).
    // It must not be silently replaced with the dev defaults here — that
    // fallback only happens when the request itself fails, and only in
    // debug builds (see IceServersRepository).
    return IceServersResult(
      config: RtcIceServerConfig(servers),
      expiresAt: _readExpiresAt(data['expiresAt']),
    );
  }

  static DateTime _readExpiresAt(Object? value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    return DateTime.now().toUtc().add(_defaultTtl);
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
