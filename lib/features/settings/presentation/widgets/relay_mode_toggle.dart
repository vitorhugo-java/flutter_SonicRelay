import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';

/// Lets the viewer force relay-only (TURN) ICE instead of a direct peer-to-peer
/// connection — useful on networks that block direct connectivity. The choice
/// is persisted and applies to the next connection.
class RelayModeToggle extends ConsumerWidget {
  const RelayModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forceRelay = ref.watch(forceRelayProvider);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: forceRelay,
      onChanged: (value) => ref.read(forceRelayProvider.notifier).set(value),
      title: const Text('Force relay (TURN only)'),
      subtitle: const Text(
        'Route audio through the relay server instead of connecting directly. '
        'Turn on for restrictive networks; leave off to prefer a direct connection.',
      ),
    );
  }
}
