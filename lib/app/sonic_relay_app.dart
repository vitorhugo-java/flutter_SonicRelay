import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    // Feed foreground/background transitions into the lifecycle controller so it
    // can start/stop the Android foreground service during an active stream.
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
