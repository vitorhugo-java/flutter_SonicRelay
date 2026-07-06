import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/http/auth_interceptor.dart';
import '../../core/http/dio_client.dart';
import '../../core/storage/secure_token_storage.dart';
import '../../core/websocket/websocket_client.dart';
import '../../features/auth/data/auth_api.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/devices/data/device_id_storage.dart';
import '../../features/devices/data/devices_api.dart';
import '../../features/devices/data/devices_repository.dart';
import '../../features/sessions/data/sessions_api.dart';
import '../../features/sessions/data/sessions_repository.dart';
import '../../features/signaling/data/signaling_client.dart';
import '../env/app_config.dart';

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
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
