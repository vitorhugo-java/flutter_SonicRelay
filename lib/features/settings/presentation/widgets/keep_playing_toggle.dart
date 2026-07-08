import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';

/// Lets the viewer keep audio playing while the app is backgrounded during an
/// active stream, via an Android foreground service with a persistent
/// notification. Persisted and on by default; it only has any effect while a
/// stream the user started is actually running.
class KeepPlayingToggle extends ConsumerWidget {
  const KeepPlayingToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keepPlaying = ref.watch(backgroundPlaybackEnabledProvider);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: keepPlaying,
      onChanged: (value) =>
          ref.read(backgroundPlaybackEnabledProvider.notifier).set(value),
      title: const Text('Keep audio playing in background'),
      subtitle: const Text(
        'Keep listening when SonicRelay is minimized or the screen is locked. '
        'A notification shows while a stream is playing in the background.',
      ),
    );
  }
}
