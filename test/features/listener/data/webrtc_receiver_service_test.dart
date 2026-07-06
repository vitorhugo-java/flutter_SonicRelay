import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/webrtc/rtc_ice_server_config.dart';
import 'package:sonic_relay/core/webrtc/rtc_peer_connection_factory.dart';
import 'package:sonic_relay/features/listener/data/audio_receiver_service.dart';
import 'package:sonic_relay/features/listener/data/webrtc_receiver_service.dart';
import 'package:sonic_relay/features/listener/domain/listener_connection_state.dart';
import 'package:sonic_relay/features/signaling/domain/signaling_message.dart';
import 'package:sonic_relay/features/signaling/domain/signaling_message_type.dart';

class FakeRtcMediaStream implements RtcMediaStream {
  FakeRtcMediaStream(this.id);

  @override
  final String id;

  @override
  Future<void> setAudioEnabled(bool enabled) async {}
}

class FakeRtcPeerConnection implements RtcPeerConnection {
  RtcSessionDescription? remoteDescription;
  RtcSessionDescription? localDescription;
  final List<RtcIceCandidate> addedCandidates = [];
  bool disposed = false;

  void Function(RtcIceCandidate candidate)? _onIceCandidate;
  void Function(RtcMediaStream stream)? _onRemoteStream;
  void Function(RtcConnectionState state)? _onConnectionState;

  @override
  set onIceCandidate(void Function(RtcIceCandidate candidate)? callback) =>
      _onIceCandidate = callback;

  @override
  set onRemoteStream(void Function(RtcMediaStream stream)? callback) =>
      _onRemoteStream = callback;

  @override
  set onConnectionState(void Function(RtcConnectionState state)? callback) =>
      _onConnectionState = callback;

  @override
  Future<void> setRemoteDescription(RtcSessionDescription description) async =>
      remoteDescription = description;

  @override
  Future<RtcSessionDescription> createAnswer() async =>
      const RtcSessionDescription(sdp: 'answer-sdp', type: 'answer');

  @override
  Future<void> setLocalDescription(RtcSessionDescription description) async =>
      localDescription = description;

  @override
  Future<void> addIceCandidate(RtcIceCandidate candidate) async =>
      addedCandidates.add(candidate);

  @override
  Future<void> dispose() async => disposed = true;

  // Test-only triggers.
  void fireLocalCandidate(RtcIceCandidate candidate) =>
      _onIceCandidate?.call(candidate);
  void fireRemoteStream(RtcMediaStream stream) => _onRemoteStream?.call(stream);
  void fireConnectionState(RtcConnectionState state) =>
      _onConnectionState?.call(state);
}

class FakeRtcPeerConnectionFactory implements RtcPeerConnectionFactory {
  final List<FakeRtcPeerConnection> created = [];

  @override
  Future<RtcPeerConnection> create(RtcIceServerConfig iceServers) async {
    final connection = FakeRtcPeerConnection();
    created.add(connection);
    return connection;
  }
}

class FakeAudioReceiverService implements AudioReceiverService {
  final List<RtcMediaStream> played = [];
  int stopCount = 0;

  @override
  bool get isPlaying => played.isNotEmpty && stopCount == 0;

  @override
  Future<void> play(RtcMediaStream stream) async => played.add(stream);

  @override
  Future<void> stop() async => stopCount++;
}

SignalingMessage _message(
  SignalingMessageType type, {
  Map<String, Object?> payload = const {},
  String? from,
}) {
  return SignalingMessage(
    type: type,
    messageId: 'id',
    sessionId: 'session-1',
    from: from,
    timestamp: DateTime.now().toUtc(),
    payload: payload,
  );
}

void main() {
  late FakeRtcPeerConnectionFactory factory;
  late FakeAudioReceiverService audio;
  late WebRtcReceiverService service;

  setUp(() {
    factory = FakeRtcPeerConnectionFactory();
    audio = FakeAudioReceiverService();
    service = WebRtcReceiverService(
      peerConnectionFactory: factory,
      audioReceiver: audio,
    );
  });

  tearDown(() => service.dispose());

  test('publisher.ready moves state to waitingForOffer', () async {
    final states = <ListenerConnectionState>[];
    service.connectionState.listen(states.add);

    await service.handleSignal(_message(SignalingMessageType.publisherReady));
    await Future<void>.delayed(Duration.zero);

    expect(states, contains(ListenerConnectionState.waitingForOffer));
  });

  test('offer sets remote description, answers, and emits webrtc.answer', () async {
    final outbound = <OutboundSignal>[];
    service.outboundSignals.listen(outbound.add);

    await service.handleSignal(
      _message(
        SignalingMessageType.webrtcOffer,
        from: 'publisher-1',
        payload: {'sdp': 'offer-sdp', 'type': 'offer'},
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final connection = factory.created.single;
    expect(connection.remoteDescription?.sdp, 'offer-sdp');
    expect(connection.localDescription?.sdp, 'answer-sdp');

    final answer = outbound.single;
    expect(answer.type, SignalingMessageType.webrtcAnswer);
    expect(answer.payload['sdp'], 'answer-sdp');
    expect(answer.to, 'publisher-1');
  });

  test('remote ICE candidate is applied to the peer connection', () async {
    await service.handleSignal(
      _message(
        SignalingMessageType.webrtcOffer,
        payload: {'sdp': 'offer-sdp', 'type': 'offer'},
      ),
    );

    await service.handleSignal(
      _message(
        SignalingMessageType.webrtcIceCandidate,
        payload: {'candidate': 'cand', 'sdpMid': '0', 'sdpMLineIndex': 0},
      ),
    );

    expect(factory.created.single.addedCandidates.single.candidate, 'cand');
  });

  test('remote ICE candidates before the offer are buffered then flushed', () async {
    await service.handleSignal(
      _message(
        SignalingMessageType.webrtcIceCandidate,
        payload: {'candidate': 'early', 'sdpMLineIndex': 0},
      ),
    );

    await service.handleSignal(
      _message(
        SignalingMessageType.webrtcOffer,
        payload: {'sdp': 'offer-sdp', 'type': 'offer'},
      ),
    );

    expect(factory.created.single.addedCandidates.single.candidate, 'early');
  });

  test('local ICE candidate is emitted as an outbound signal', () async {
    final outbound = <OutboundSignal>[];
    service.outboundSignals.listen(outbound.add);

    await service.handleSignal(
      _message(
        SignalingMessageType.webrtcOffer,
        from: 'publisher-1',
        payload: {'sdp': 'offer-sdp', 'type': 'offer'},
      ),
    );
    factory.created.single.fireLocalCandidate(
      const RtcIceCandidate(candidate: 'local-cand', sdpMid: '0', sdpMLineIndex: 0),
    );
    await Future<void>.delayed(Duration.zero);

    final ice = outbound.firstWhere(
      (signal) => signal.type == SignalingMessageType.webrtcIceCandidate,
    );
    expect(ice.payload['candidate'], 'local-cand');
    expect(ice.to, 'publisher-1');
  });

  test('remote stream is handed to the audio receiver', () async {
    await service.handleSignal(
      _message(
        SignalingMessageType.webrtcOffer,
        payload: {'sdp': 'offer-sdp', 'type': 'offer'},
      ),
    );

    factory.created.single.fireRemoteStream(FakeRtcMediaStream('remote-1'));
    await Future<void>.delayed(Duration.zero);

    expect(audio.played.single.id, 'remote-1');
  });

  test('connection state transitions map to listener state and stats', () async {
    final states = <ListenerConnectionState>[];
    service.connectionState.listen(states.add);

    await service.handleSignal(
      _message(
        SignalingMessageType.webrtcOffer,
        payload: {'sdp': 'offer-sdp', 'type': 'offer'},
      ),
    );
    factory.created.single.fireConnectionState(RtcConnectionState.connected);
    await Future<void>.delayed(Duration.zero);

    expect(states, contains(ListenerConnectionState.connected));
    expect(service.statsValue.iceState, 'Connected');
    expect(service.statsValue.connectedAt, isNotNull);
  });

  test('session.ended tears down the peer connection and stops audio', () async {
    final states = <ListenerConnectionState>[];
    service.connectionState.listen(states.add);

    await service.handleSignal(
      _message(
        SignalingMessageType.webrtcOffer,
        payload: {'sdp': 'offer-sdp', 'type': 'offer'},
      ),
    );
    final connection = factory.created.single;

    await service.handleSignal(_message(SignalingMessageType.sessionEnded));
    await Future<void>.delayed(Duration.zero);

    expect(connection.disposed, isTrue);
    expect(audio.stopCount, greaterThanOrEqualTo(1));
    expect(states.last, ListenerConnectionState.disconnected);
  });

  test('a second offer renegotiates by disposing the previous connection', () async {
    await service.handleSignal(
      _message(
        SignalingMessageType.webrtcOffer,
        payload: {'sdp': 'offer-1', 'type': 'offer'},
      ),
    );
    await service.handleSignal(
      _message(
        SignalingMessageType.webrtcOffer,
        payload: {'sdp': 'offer-2', 'type': 'offer'},
      ),
    );

    expect(factory.created, hasLength(2));
    expect(factory.created.first.disposed, isTrue);
    expect(factory.created.last.remoteDescription?.sdp, 'offer-2');
  });
}
