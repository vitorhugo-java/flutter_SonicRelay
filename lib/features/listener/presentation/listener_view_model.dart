import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/app_providers.dart';
import '../../sessions/domain/stream_session.dart';
import '../../signaling/data/signaling_client.dart';
import '../../signaling/domain/signaling_message.dart';
import '../data/webrtc_receiver_service.dart';
import '../domain/listener_connection_state.dart';
import '../domain/listener_stats.dart';

class ListenerState {
  const ListenerState({
    this.connection = ListenerConnectionState.idle,
    this.stats = const ListenerStats.initial(),
    this.signaling,
  });

  final ListenerConnectionState connection;
  final ListenerStats stats;

  /// Signaling socket status, or `null` before the socket reports anything.
  final SignalingConnectionState? signaling;

  ListenerState copyWith({
    ListenerConnectionState? connection,
    ListenerStats? stats,
    SignalingConnectionState? signaling,
  }) {
    return ListenerState(
      connection: connection ?? this.connection,
      stats: stats ?? this.stats,
      signaling: signaling ?? this.signaling,
    );
  }
}

final listenerViewModelProvider =
    NotifierProvider<ListenerViewModel, ListenerState>(ListenerViewModel.new);

/// Bridges the signaling client and the WebRTC receiver for the listener UI:
/// inbound signaling messages drive the receiver, and the answers/candidates
/// the receiver produces are forwarded back out through the signaling client.
class ListenerViewModel extends Notifier<ListenerState> {
  late final SignalingClient _signaling;
  late final WebRtcReceiverService _receiver;
  StreamSubscription<SignalingMessage>? _messageSubscription;
  StreamSubscription<OutboundSignal>? _outboundSubscription;
  StreamSubscription<ListenerConnectionState>? _connectionSubscription;
  StreamSubscription<ListenerStats>? _statsSubscription;
  StreamSubscription<SignalingConnectionState>? _signalingStateSubscription;

  @override
  ListenerState build() {
    _signaling = ref.watch(signalingClientProvider);
    _receiver = ref.watch(webRtcReceiverServiceProvider);

    _messageSubscription = _signaling.messages.listen(_receiver.handleSignal);
    _outboundSubscription = _receiver.outboundSignals.listen((signal) {
      _signaling.send(signal.type, signal.payload, to: signal.to);
    });
    _connectionSubscription = _receiver.connectionState.listen((connection) {
      state = state.copyWith(connection: connection);
      // Drive the background foreground-service decision from the same states.
      ref
          .read(streamLifecycleControllerProvider)
          .onConnectionState(connection);
    });
    _statsSubscription = _receiver.stats.listen((stats) {
      state = state.copyWith(stats: stats);
    });
    _signalingStateSubscription = _signaling.connectionState.listen((signaling) {
      state = state.copyWith(signaling: signaling);
    });

    ref.onDispose(() {
      _messageSubscription?.cancel();
      _outboundSubscription?.cancel();
      _connectionSubscription?.cancel();
      _statsSubscription?.cancel();
      _signalingStateSubscription?.cancel();
    });

    return ListenerState(
      connection: _receiver.connectionStateValue,
      stats: _receiver.statsValue,
    );
  }

  /// Opens the signaling socket for [session]. Inbound messages are already
  /// routed to the WebRTC receiver (wired in [build]), so once connected the
  /// publisher handshake (`viewer.ready` -> offer -> answer) proceeds on its
  /// own. Throws if the socket cannot be opened.
  Future<void> connect({
    required StreamSession session,
    required String deviceId,
  }) => _signaling.connect(session: session, deviceId: deviceId);

  /// Nudges a stalled connection to recover by re-announcing readiness to the
  /// publisher (invoked from the background notification's "Reconnect" action).
  Future<void> reconnect() => _receiver.reconnect();

  /// Leaves the session: tears down the peer connection/audio and closes the
  /// signaling socket.
  Future<void> leave() async {
    await _receiver.leave();
    await _signaling.leave();
  }
}
