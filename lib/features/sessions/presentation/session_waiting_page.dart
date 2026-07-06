import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di/app_providers.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/diagnostics/sonic_log.dart';
import '../../../core/widgets/connection_badge.dart';
import '../../../core/widgets/sonic_button.dart';
import '../../../core/widgets/sonic_card.dart';
import '../../listener/presentation/listener_view_model.dart';
import 'join_session_view_model.dart';

class SessionWaitingPage extends ConsumerStatefulWidget {
  const SessionWaitingPage({super.key});

  @override
  ConsumerState<SessionWaitingPage> createState() => _SessionWaitingPageState();
}

class _SessionWaitingPageState extends ConsumerState<SessionWaitingPage> {
  bool _started = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;

    final session = ref.read(joinSessionViewModelProvider).session;
    if (session == null) return;

    final deviceId = await ref
        .read(devicesRepositoryProvider)
        .readCurrentDeviceId();
    sonicLog(
      'Waiting',
      'start sessionId=${session.sessionId} deviceId=$deviceId',
    );
    if (deviceId == null || deviceId.isEmpty) {
      sonicLog('Waiting', 'no device id -> cannot connect');
      if (mounted) {
        setState(
          () => _error =
              'This viewer is not registered yet. Rejoin to continue.',
        );
      }
      return;
    }

    try {
      // Instantiating the notifier wires the signaling -> receiver bridge
      // before the socket opens, then connect() starts the handshake.
      await ref
          .read(listenerViewModelProvider.notifier)
          .connect(session: session, deviceId: deviceId);
    } catch (error) {
      sonicLog('Waiting', 'connect failed: $error');
      if (mounted) {
        setState(
          () => _error = 'Unable to connect to the session stream. Try again.',
        );
      }
      return;
    }

    sonicLog('Waiting', 'signaling opened -> navigating to /listener');
    if (mounted) context.go('/listener');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(joinSessionViewModelProvider).session;
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Session')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SonicButton(
                label: 'Enter a session code',
                onPressed: () => context.go('/join'),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Preparing stream')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SonicCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConnectionBadge(
                    label: _error == null
                        ? 'Connecting to signaling'
                        : 'Connection failed',
                    status: _error == null
                        ? ConnectionStatus.connecting
                        : ConnectionStatus.disconnected,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Session ${session.sessionId}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error ?? 'Signaling host: ${session.signalingUrl.host}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    SonicButton(
                      label: 'Back to session code',
                      icon: Icons.arrow_back_rounded,
                      isSecondary: true,
                      onPressed: () => context.go('/join'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
