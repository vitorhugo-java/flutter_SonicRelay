import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/core/storage/secure_token_storage.dart';
import 'package:sonic_relay/core/webrtc/rtc_peer_connection_factory.dart';
import 'package:sonic_relay/core/websocket/websocket_client.dart';
import 'package:sonic_relay/features/auth/domain/auth_session.dart';
import 'package:sonic_relay/features/listener/data/audio_receiver_service.dart';
import 'package:sonic_relay/features/listener/presentation/listener_view_model.dart';
import 'package:sonic_relay/features/sessions/domain/stream_session.dart';
import 'package:sonic_relay/features/signaling/data/signaling_client.dart';

class FakeAudioReceiverService implements AudioReceiverService {
  int stopCount = 0;

  @override
  bool get isPlaying => false;

  @override
  Future<void> play(RtcMediaStream stream) async {}

  @override
  Future<void> stop() async => stopCount++;
}

class FakeWebSocketConnection implements WebSocketConnection {
  final _controller = StreamController<dynamic>.broadcast();
  bool closed = false;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void add(String data) {}

  @override
  Future<void> close() async {
    closed = true;
    await _controller.close();
  }
}

class FakeTokenStorage implements TokenStorage {
  @override
  Future<AuthSession?> read() async => null;

  @override
  Future<void> write(AuthSession session) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  test('leave tears down the receiver and closes the signaling socket', () async {
    final audio = FakeAudioReceiverService();
    late FakeWebSocketConnection connection;
    final webSocketClient = WebSocketClient(
      connector: (uri, headers) async {
        connection = FakeWebSocketConnection();
        return connection;
      },
      scheduleTimer: (delay, callback) => Timer(Duration.zero, callback),
    );
    final signalingClient = SignalingClient(
      webSocketClient: webSocketClient,
      tokenStorage: FakeTokenStorage(),
    );

    final container = ProviderContainer(
      overrides: [
        audioReceiverServiceProvider.overrideWithValue(audio),
        signalingClientProvider.overrideWithValue(signalingClient),
      ],
    );
    addTearDown(container.dispose);

    // Force the receiver + view model to build and subscribe.
    container.read(listenerViewModelProvider);

    await signalingClient.connect(
      session: StreamSession(
        sessionId: 'session-1',
        role: 'viewer',
        signalingUrl: Uri.parse('wss://stream.example/ws/signaling'),
      ),
      deviceId: 'device-1',
    );
    await Future<void>.delayed(Duration.zero);

    await container.read(listenerViewModelProvider.notifier).leave();

    expect(audio.stopCount, greaterThanOrEqualTo(1));
    expect(connection.closed, isTrue);
  });
}
