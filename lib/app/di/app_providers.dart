import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/http/auth_interceptor.dart';
import '../../core/http/dio_client.dart';
import '../../core/storage/secure_token_storage.dart';
import '../../core/storage/server_config_storage.dart';
import '../../core/webrtc/ice_servers_api.dart';
import '../../core/webrtc/ice_servers_repository.dart';
import '../../core/webrtc/rtc_ice_server_config.dart';
import '../../core/webrtc/rtc_peer_connection_factory.dart';
import '../../core/websocket/websocket_client.dart';
import '../../features/auth/data/auth_api.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/devices/data/device_id_storage.dart';
import '../../features/devices/data/devices_api.dart';
import '../../features/devices/data/devices_repository.dart';
import '../../features/sessions/data/sessions_api.dart';
import '../../features/sessions/data/sessions_repository.dart';
import '../../features/listener/data/audio_receiver_service.dart';
import '../../features/listener/data/webrtc_receiver_service.dart';
import '../../features/signaling/data/signaling_client.dart';
import '../env/app_config.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

final serverConfigStorageProvider = Provider<ServerConfigStorage>(
  (ref) => ServerConfigStorage(ref.watch(secureStorageProvider)),
);

/// Holds the currently configured server base URL. The initial value is
/// injected at startup via an override in `main()` with the persisted URL
/// (falling back to [AppConfig.defaultServerUrl]). Updating it persists the
/// new URL and rebuilds every provider that depends on [appConfigProvider].
final serverUrlProvider = NotifierProvider<ServerUrlNotifier, String>(
  ServerUrlNotifier.new,
);

class ServerUrlNotifier extends Notifier<String> {
  ServerUrlNotifier([this._initialUrl = AppConfig.defaultServerUrl]);

  final String _initialUrl;

  @override
  String build() => AppConfig.normalizeServerUrl(_initialUrl);

  Future<void> update(String url) async {
    final normalized = AppConfig.normalizeServerUrl(url);
    await ref.read(serverConfigStorageProvider).write(normalized);
    state = normalized;
  }

  Future<void> reset() async {
    await ref.read(serverConfigStorageProvider).clear();
    state = AppConfig.normalizeServerUrl(AppConfig.defaultServerUrl);
  }
}

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromServerUrl(ref.watch(serverUrlProvider)),
);

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => SecureTokenStorage(ref.watch(secureStorageProvider)),
);

final authInterceptorProvider = Provider<AuthInterceptor>((ref) {
  final config = ref.watch(appConfigProvider);
  return AuthInterceptor(
    tokenStorage: ref.watch(tokenStorageProvider),
    refreshDio: createRefreshDio(config),
  );
});

final dioProvider = Provider<Dio>((ref) {
  return createDioClient(
    ref.watch(appConfigProvider),
    ref.watch(authInterceptorProvider),
  );
});

final authApiProvider = Provider<AuthApi>(
  (ref) => DioAuthApi(ref.watch(dioProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    api: ref.watch(authApiProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
  ),
);

final deviceIdStorageProvider = Provider<DeviceIdStorage>(
  (ref) => SecureDeviceIdStorage(ref.watch(secureStorageProvider)),
);

final devicesApiProvider = Provider<DevicesApi>(
  (ref) => DioDevicesApi(ref.watch(dioProvider)),
);

final devicesRepositoryProvider = Provider<DevicesRepository>(
  (ref) => DevicesRepository(
    api: ref.watch(devicesApiProvider),
    deviceIdStorage: ref.watch(deviceIdStorageProvider),
  ),
);

final sessionsApiProvider = Provider<SessionsApi>(
  (ref) => DioSessionsApi(ref.watch(dioProvider)),
);

final sessionsRepositoryProvider = Provider<SessionsRepository>(
  (ref) => SessionsRepository(
    api: ref.watch(sessionsApiProvider),
    devicesRepository: ref.watch(devicesRepositoryProvider),
    config: ref.watch(appConfigProvider),
  ),
);

final devicePlatformProvider = Provider<String>(
  (ref) => Platform.operatingSystem,
);

final webSocketClientProvider = Provider<WebSocketClient>(
  (ref) => WebSocketClient(connector: ioWebSocketConnector),
);

final signalingClientProvider = Provider<SignalingClient>(
  (ref) => SignalingClient(
    webSocketClient: ref.watch(webSocketClientProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
  ),
);

final rtcIceServerConfigProvider = Provider<RtcIceServerConfig>(
  (ref) => RtcIceServerConfig.defaults(),
);

final iceServersApiProvider = Provider<IceServersApi>(
  (ref) => DioIceServersApi(ref.watch(dioProvider)),
);

final iceServersRepositoryProvider = Provider<IceServersRepository>(
  (ref) => IceServersRepository(api: ref.watch(iceServersApiProvider)),
);

final rtcPeerConnectionFactoryProvider = Provider<RtcPeerConnectionFactory>(
  (ref) => const FlutterWebRtcPeerConnectionFactory(),
);

final audioReceiverServiceProvider = Provider<AudioReceiverService>(
  (ref) => WebRtcAudioReceiverService(),
);

final webRtcReceiverServiceProvider = Provider<WebRtcReceiverService>((ref) {
  final service = WebRtcReceiverService(
    peerConnectionFactory: ref.watch(rtcPeerConnectionFactoryProvider),
    audioReceiver: ref.watch(audioReceiverServiceProvider),
    iceServers: ref.watch(rtcIceServerConfigProvider),
    iceServersResolver: ref.watch(iceServersRepositoryProvider).resolve,
  );
  ref.onDispose(service.dispose);
  return service;
});
