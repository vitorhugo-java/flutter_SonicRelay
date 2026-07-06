import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/app_providers.dart';
import '../../sessions/domain/stream_session.dart';
import '../data/signaling_client.dart';
import '../domain/signaling_message.dart';

enum SignalingStatus {
  idle,
  connecting,
  connected,
  reconnecting,
  ended,
  disconnected,
  error,
}

class SignalingStatusState {
  const SignalingStatusState({
    this.status = SignalingStatus.idle,
    this.errorMessage,
    this.lastMessage,
  });

  final SignalingStatus status;
  final String? errorMessage;
  final SignalingMessage? lastMessage;
}

final signalingStatusViewModelProvider =
    NotifierProvider<SignalingStatusViewModel, SignalingStatusState>(
      SignalingStatusViewModel.new,
    );

/// Exposes signaling connection status and routed messages to listener
/// feature UI, backed by [SignalingClient].
class SignalingStatusViewModel extends Notifier<SignalingStatusState> {
  late final SignalingClient _client;
  StreamSubscription<SignalingConnectionState>? _connectionSubscription;
  StreamSubscription<SignalingMessage>? _messageSubscription;

  @override
  SignalingStatusState build() {
    _client = ref.watch(signalingClientProvider);
    _connectionSubscription = _client.connectionState.listen(
      _handleConnectionState,
    );
    _messageSubscription = _client.messages.listen(_handleMessage);
    ref.onDispose(() {
      _connectionSubscription?.cancel();
      _messageSubscription?.cancel();
    });
    return const SignalingStatusState();
  }

  Future<void> connect({
    required StreamSession session,
    required String deviceId,
  }) async {
    state = const SignalingStatusState(status: SignalingStatus.connecting);
    try {
      await _client.connect(session: session, deviceId: deviceId);
    } catch (_) {
      state = const SignalingStatusState(
        status: SignalingStatus.error,
        errorMessage: 'Unable to connect to the session stream.',
      );
    }
  }

  Future<void> leave() => _client.leave();

  void _handleConnectionState(SignalingConnectionState value) {
    state = SignalingStatusState(
      status: _mapStatus(value),
      lastMessage: state.lastMessage,
    );
  }

  void _handleMessage(SignalingMessage message) {
    state = SignalingStatusState(status: state.status, lastMessage: message);
  }

  SignalingStatus _mapStatus(SignalingConnectionState value) =>
      switch (value) {
        SignalingConnectionState.connecting => SignalingStatus.connecting,
        SignalingConnectionState.connected => SignalingStatus.connected,
        SignalingConnectionState.reconnecting => SignalingStatus.reconnecting,
        SignalingConnectionState.ended => SignalingStatus.ended,
        SignalingConnectionState.disconnected =>
          SignalingStatus.disconnected,
      };
}
