import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/connection_badge.dart';
import '../../../core/widgets/sonic_button.dart';
import '../../../core/widgets/sonic_card.dart';
import '../domain/listener_connection_state.dart';
import 'listener_view_model.dart';

class ListenerPage extends ConsumerWidget {
  const ListenerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(listenerViewModelProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio monitor'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ConnectionBadge(
                      label: _badgeLabel(state.connection),
                      status: _badgeStatus(state.connection),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SonicCard(child: _Visualizer(active: state.stats.hasRemoteAudio)),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          label: 'Audio',
                          value: state.stats.hasRemoteAudio ? 'Live' : 'Silent',
                          icon: Icons.graphic_eq_rounded,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _MetricCard(
                          label: 'ICE state',
                          value: state.stats.iceState,
                          icon: Icons.hub_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SonicButton(
                    label: 'Leave session',
                    icon: Icons.logout_rounded,
                    isSecondary: true,
                    onPressed: () async {
                      await ref.read(listenerViewModelProvider.notifier).leave();
                      if (context.mounted) context.go('/join');
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _badgeLabel(ListenerConnectionState state) => switch (state) {
    ListenerConnectionState.idle => 'Not connected',
    ListenerConnectionState.waitingForOffer => 'Waiting for publisher',
    ListenerConnectionState.negotiating => 'Negotiating',
    ListenerConnectionState.connecting => 'Connecting',
    ListenerConnectionState.connected => 'Listening',
    ListenerConnectionState.failed => 'Connection failed',
    ListenerConnectionState.disconnected => 'Disconnected',
  };

  ConnectionStatus _badgeStatus(ListenerConnectionState state) => switch (state) {
    ListenerConnectionState.connected => ConnectionStatus.connected,
    ListenerConnectionState.waitingForOffer ||
    ListenerConnectionState.negotiating ||
    ListenerConnectionState.connecting => ConnectionStatus.connecting,
    ListenerConnectionState.idle ||
    ListenerConnectionState.failed ||
    ListenerConnectionState.disconnected => ConnectionStatus.disconnected,
  };
}

class _Visualizer extends StatelessWidget {
  const _Visualizer({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    const heights = [30.0, 52.0, 76.0, 44.0, 88.0, 62.0, 36.0, 70.0, 48.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Live signal', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          active ? 'Receiving remote audio' : 'Visualizer preview',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        ExcludeSemantics(
          child: Opacity(
            opacity: active ? 1 : 0.4,
            child: SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final height in heights)
                    Expanded(
                      child: Container(
                        height: height,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [AppColors.accent, Color(0xFF438BFF)],
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SonicCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.accent),
          const SizedBox(height: AppSpacing.md),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}
