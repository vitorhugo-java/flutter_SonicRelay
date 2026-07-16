import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'app/di/app_providers.dart';
import 'app/env/app_config.dart';
import 'app/sonic_relay_app.dart';
import 'core/storage/background_playback_storage.dart';
import 'core/storage/relay_mode_storage.dart';
import 'core/storage/server_config_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const secureStorage = FlutterSecureStorage();
  final savedServerUrl =
      await const ServerConfigStorage(secureStorage).read() ??
      AppConfig.defaultServerUrl;
  final savedForceRelay = await const RelayModeStorage(secureStorage).read();
  final savedKeepPlaying =
      await const BackgroundPlaybackStorage(secureStorage).read();
  final diagnosticsDirectory = (await getApplicationSupportDirectory()).path;

  runApp(
    ProviderScope(
      overrides: [
        serverUrlProvider.overrideWith(() => ServerUrlNotifier(savedServerUrl)),
        forceRelayProvider.overrideWith(() => ForceRelayNotifier(savedForceRelay)),
        backgroundPlaybackEnabledProvider.overrideWith(
          () => BackgroundPlaybackNotifier(savedKeepPlaying),
        ),
        diagnosticsDirectoryProvider.overrideWithValue(diagnosticsDirectory),
      ],
      child: const SonicRelayApp(),
    ),
  );
}
