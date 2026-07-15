import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/diagnostics/sonic_log.dart';
import 'di/app_providers.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import '../features/devices/presentation/devices_view_model.dart';

class SonicRelayApp extends ConsumerStatefulWidget {
  const SonicRelayApp({super.key});

  @override
  ConsumerState<SonicRelayApp> createState() => _SonicRelayAppState();
}

class _SonicRelayAppState extends ConsumerState<SonicRelayApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive/hidden/paused/detached must only ever update UI/service
    // visibility (via the lifecycle controller below), never be treated as an
    // explicit leave — only a user-initiated Stop/Leave, logout, or terminal
    // connection state closes the active stream.
    sonicLog('Lifecycle', 'app lifecycle -> $state');
    final inForeground = state == AppLifecycleState.resumed;
    ref
        .read(streamLifecycleControllerProvider)
        .onAppForegroundChanged(inForeground);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(devicesViewModelProvider);
    return MaterialApp.router(
      title: 'SonicRelay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
