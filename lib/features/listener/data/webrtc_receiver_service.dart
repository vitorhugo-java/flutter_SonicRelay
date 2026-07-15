import 'dart:async';

import '../../../core/diagnostics/sonic_log.dart';
import '../../../core/webrtc/rtc_ice_server_config.dart';
import '../../../core/webrtc/rtc_peer_connection_factory.dart';
import '../../signaling/domain/signaling_message.dart';
import '../../signaling/domain/signaling_message_type.dart';
import '../domain/listener_connection_state.dart';
import '../domain/listener_stats.dart';
import 'audio_receiver_service.dart';

/// A signaling message the receiver wants sent back through the signaling
/// feature (a `webrtc.answer` or a local `webrtc.ice_candidate`).
class OutboundSignal {
  const OutboundSignal(this.type, this.payload, {this.to});

  final SignalingMessageType type;
  final Map<String, Object?> payload;
  final String? to;
}

/// Owns the receive-only WebRTC peer-connection lifecycle for the viewer.
///
/// Deliberately signaling-agnostic: inbound protocol messages are pushed in via
/// [handleSignal], and answers/candidates the receiver produces are emitted on
/// [outboundSignals] for the view model to forward. It never adds a local
/// track, never captures a microphone, and only ever consumes remote audio.
class WebRtcReceiverService {
  WebRtcReceiverService({
    required RtcPeerConnectionFactory peerConnectionFactory,
    required AudioReceiverService audioReceiver,
    RtcIceServerConfig? iceServers,
    Future<RtcIceServerConfig> Function()? iceServersResolver,
    bool Function()? forceRelay,
    Duration statsInterval = const Duration(seconds: 2),
  }) : _peerConnectionFactory = peerConnectionFactory,
       _audioReceiver = audioReceiver,
       _iceServers = iceServers ?? RtcIceServerConfig.defaults(),
       _iceServersResolver = iceServersResolver,
       _forceRelay = forceRelay,
       _statsInterval = statsInterval;

  final RtcPeerConnectionFactory _peerConnectionFactory;
  final AudioReceiverService _audioReceiver;
  final RtcIceServerConfig _iceServers;

  /// Optional resolver used to fetch fresh ICE servers (including short-lived
  /// TURN credentials) at negotiation time. Falls back to [_iceServers] when
  /// absent. Must never throw — the repository swallows failures into a
  /// fallback config.
  final Future<RtcIceServerConfig> Function()? _iceServersResolver;

  /// Reads the user's relay-only preference at negotiation time (dynamic so a
  /// toggle applies to the next connection). Null/false allows direct ICE.
  final bool Function()? _forceRelay;
  final Duration _statsInterval;
  Timer? _statsTimer;

  final _connectionStateController =
      StreamController<ListenerConnectionState>.broadcast();
  final _statsController = StreamController<ListenerStats>.broadcast();
  final _outboundController = StreamController<OutboundSignal>.broadcast();

  RtcPeerConnection? _peerConnection;
  bool _remoteDescriptionSet = false;
  final List<RtcIceCandidate> _pendingRemoteCandidates = [];
  String? _publisherId;

  /// Cumulative inbound counters from the previous poll, so interval metrics
  /// (loss %, concealment %, jitter-buffer delay) reflect the recent network
  /// behavior instead of a lifetime average. Reset per peer connection.
  RtcInboundAudioStats? _previousInboundAudio;

  ListenerConnectionState _state = ListenerConnectionState.idle;
  ListenerStats _stats = const ListenerStats.initial();

  Stream<ListenerConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<ListenerStats> get stats => _statsController.stream;
  Stream<OutboundSignal> get outboundSignals => _outboundController.stream;

  ListenerConnectionState get connectionStateValue => _state;
  ListenerStats get statsValue => _stats;

  /// Routes an inbound signaling message. Non-WebRTC messages are ignored.
  Future<void> handleSignal(SignalingMessage message) async {
    switch (message.type) {
      case SignalingMessageType.sessionJoined:
        // If the publisher joined before us, the backend delivers its presence
        // here (role=publisher, `from`=publisher id) rather than as a separate
        // `publisher.ready`. Announce `viewer.ready` to it so it creates its peer
        // connection and sends the offer. This covers the viewer-connects-first
        // and reconnect cases that a publisher-side `session.joined` trigger
        // cannot see. Our own join carries no `from`, so it is ignored.
        if (message.from != null && message.payload['role'] == 'publisher') {
          _publisherId = message.from;
          _emit(SignalingMessageType.viewerReady, const {}, to: message.from);
        }
        if (_state == ListenerConnectionState.idle) {
          _setState(ListenerConnectionState.waitingForOffer);
        }
      case SignalingMessageType.publisherReady:
        // The publisher announces itself; learn its participant id from the
        // authenticated `from` and reply `viewer.ready` to it so the publisher
        // creates its peer connection and sends the offer. `viewer.ready` is a
        // routed message and the backend rejects it without a `to` recipient.
        sonicLog('WebRTC', 'publisher.ready from=${message.from} -> viewer.ready');
        _publisherId = message.from;
        _emit(SignalingMessageType.viewerReady, const {}, to: message.from);
        if (_state == ListenerConnectionState.idle) {
          _setState(ListenerConnectionState.waitingForOffer);
        }
      case SignalingMessageType.webrtcOffer:
        await _handleOffer(message);
      case SignalingMessageType.webrtcIceCandidate:
        await _handleRemoteCandidate(message);
      case SignalingMessageType.sessionEnded:
        await _teardown(ListenerConnectionState.ended);
      case SignalingMessageType.sessionLeft:
        await _teardown(ListenerConnectionState.disconnected);
      case SignalingMessageType.participantReconnected:
        // The publisher's signaling socket reconnected within the backend's
        // grace period. We're the answerer and cannot restart ICE ourselves,
        // so nudge it to re-offer instead of waiting indefinitely for it to
        // notice on its own. Ignore reconnects of other participants (e.g.
        // another viewer in the same session) — we only ever talk to the
        // publisher.
        if (message.from != null && message.from == _publisherId) {
          sonicLog(
            'WebRTC',
            'participant.reconnected from=${message.from} -> viewer.ready',
          );
          _emit(SignalingMessageType.viewerReady, const {}, to: message.from);
        }
      case SignalingMessageType.participantDisconnected:
        // Transient — the backend's grace period is running. The peer
        // connection (if any) is left alone; nothing to do here.
        break;
      default:
        break;
    }
  }

  Future<void> _handleOffer(SignalingMessage message) async {
    _publisherId = message.from;
    sonicLog('WebRTC', 'offer received from=${message.from} -> negotiating');
    try {
      // Renegotiate cleanly if an offer arrives while a connection exists.
      await _disposePeerConnection();
      _setState(ListenerConnectionState.negotiating);

      // Resolve ICE servers (with fresh TURN credentials) per negotiation; the
      // resolver never throws, falling back to the static config on failure.
      final resolved = _iceServersResolver != null
          ? await _iceServersResolver()
          : _iceServers;
      final iceServers = (_forceRelay?.call() ?? false)
          ? resolved.withRelay(true)
          : resolved;
      final connection = await _peerConnectionFactory.create(iceServers);
      _peerConnection = connection;
      connection.onIceCandidate = _handleLocalCandidate;
      connection.onRemoteStream = _handleRemoteStream;
      connection.onConnectionState = _handleConnectionState;

      final offer = RtcSessionDescription.fromSignalingPayload(message.payload);
      await connection.setRemoteDescription(offer);
      _remoteDescriptionSet = true;
      await _flushPendingCandidates();

      final answer = await connection.createAnswer();
      await connection.setLocalDescription(answer);

      sonicLog('WebRTC', 'answer created -> sending to=$_publisherId');
      _emit(
        SignalingMessageType.webrtcAnswer,
        answer.toSignalingPayload(),
        to: _publisherId,
      );
    } catch (error, stack) {
      sonicLog('WebRTC', 'offer handling failed: $error\n$stack');
      await _teardown(ListenerConnectionState.failed);
    }
  }

  Future<void> _handleRemoteCandidate(SignalingMessage message) async {
    final candidate = RtcIceCandidate.fromSignalingPayload(message.payload);
    final connection = _peerConnection;
    if (connection == null || !_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }
    await connection.addIceCandidate(candidate);
  }

  Future<void> _flushPendingCandidates() async {
    final connection = _peerConnection;
    if (connection == null) return;
    final pending = List<RtcIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      await connection.addIceCandidate(candidate);
    }
  }

  void _handleLocalCandidate(RtcIceCandidate candidate) {
    _emit(
      SignalingMessageType.webrtcIceCandidate,
      candidate.toSignalingPayload(),
      to: _publisherId,
    );
  }

  Future<void> _handleRemoteStream(RtcMediaStream stream) async {
    sonicLog('WebRTC', 'remote audio stream received -> playing');
    await _audioReceiver.play(stream);
    _setStats(_stats.copyWith(hasRemoteAudio: true));
  }

  void _handleConnectionState(RtcConnectionState state) {
    sonicLog('WebRTC', 'peer connection state -> $state');
    switch (state) {
      case RtcConnectionState.connecting:
        _stopStatsPolling();
        _setStats(_stats.copyWith(iceState: 'Connecting'));
        _setState(ListenerConnectionState.connecting);
      case RtcConnectionState.connected:
        _setStats(
          _stats.copyWith(iceState: 'Connected', connectedAt: DateTime.now()),
        );
        _setState(ListenerConnectionState.connected);
        _startStatsPolling();
      case RtcConnectionState.disconnected:
        // Transient ICE loss: keep the peer connection alive, it may recover.
        _stopStatsPolling();
        _setStats(_stats.copyWith(iceState: 'Reconnecting'));
        _setState(ListenerConnectionState.reconnecting);
      case RtcConnectionState.failed:
        _stopStatsPolling();
        _setStats(_stats.copyWith(iceState: 'Failed'));
        _setState(ListenerConnectionState.failed);
      case RtcConnectionState.closed:
        _stopStatsPolling();
        _setStats(_stats.copyWith(iceState: 'Closed'));
        _setState(ListenerConnectionState.disconnected);
      case RtcConnectionState.idle:
        break;
    }
  }

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(_statsInterval, (_) => refreshStats());
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  /// Polls the peer connection for coarse stats (RTT, jitter, transport mode,
  /// inbound loss/concealment counters) and folds them into [statsValue].
  /// Public so the periodic poll is testable without a real timer.
  Future<void> refreshStats() async {
    final connection = _peerConnection;
    if (connection == null) return;
    final stats = await connection.getStats();
    if (stats == null) return;

    final inbound = stats.inboundAudio;
    double? packetLossPercent;
    double? concealmentPercent;
    double? jitterBufferDelayMs;
    if (inbound != null) {
      // On the first poll of a connection the previous counters are zero, so
      // the first interval covers everything since the connection came up.
      final previous = _previousInboundAudio;
      packetLossPercent = _intervalRatio(
        _delta(previous?.packetsLost, inbound.packetsLost),
        _sum(
          _delta(previous?.packetsReceived, inbound.packetsReceived),
          _delta(previous?.packetsLost, inbound.packetsLost),
        ),
        scale: 100,
      );
      concealmentPercent = _intervalRatio(
        _delta(previous?.concealedSamples, inbound.concealedSamples),
        _delta(previous?.totalSamplesReceived, inbound.totalSamplesReceived),
        scale: 100,
      );
      jitterBufferDelayMs = _intervalRatio(
        _delta(
          previous?.jitterBufferDelaySeconds,
          inbound.jitterBufferDelaySeconds,
        ),
        _delta(
          previous?.jitterBufferEmittedCount,
          inbound.jitterBufferEmittedCount,
        ),
        scale: 1000,
      );
      _previousInboundAudio = inbound;
    }

    _setStats(
      _stats.copyWith(
        rttMs: stats.rttMs,
        jitterMs: stats.jitterMs,
        transport: stats.transport,
        packetLossPercent: packetLossPercent,
        concealmentPercent: concealmentPercent,
        jitterBufferDelayMs: jitterBufferDelayMs,
        packetsReceived: inbound?.packetsReceived,
        packetsLost: inbound?.packetsLost,
        packetsDiscarded: inbound?.packetsDiscarded,
        fecPacketsReceived: inbound?.fecPacketsReceived,
        concealmentEvents: inbound?.concealmentEvents,
      ),
    );
  }

  /// Delta between successive cumulative counters, clamped at zero so a stats
  /// reset (renegotiation, SSRC change) never yields negative intervals.
  static double? _delta(num? previous, num? current) {
    if (current == null) return null;
    final delta = current.toDouble() - (previous?.toDouble() ?? 0);
    return delta < 0 ? 0 : delta;
  }

  static double? _sum(double? a, double? b) =>
      a == null || b == null ? null : a + b;

  /// `numerator / denominator * scale`, or null when either side is missing or
  /// the interval carried no traffic (denominator zero).
  static double? _intervalRatio(
    double? numerator,
    double? denominator, {
    required double scale,
  }) {
    if (numerator == null || denominator == null || denominator <= 0) {
      return null;
    }
    return numerator / denominator * scale;
  }

  void _emit(
    SignalingMessageType type,
    Map<String, Object?> payload, {
    String? to,
  }) {
    if (_outboundController.isClosed) return;
    _outboundController.add(OutboundSignal(type, payload, to: to));
  }

  void _setState(ListenerConnectionState state) {
    _state = state;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  void _setStats(ListenerStats stats) {
    _stats = stats;
    if (!_statsController.isClosed) {
      _statsController.add(stats);
    }
  }

  Future<void> _disposePeerConnection() async {
    _remoteDescriptionSet = false;
    _previousInboundAudio = null;
    final connection = _peerConnection;
    _peerConnection = null;
    if (connection != null) {
      await connection.dispose();
    }
  }

  Future<void> _teardown(ListenerConnectionState finalState) async {
    _stopStatsPolling();
    await _disposePeerConnection();
    _pendingRemoteCandidates.clear();
    await _audioReceiver.stop();
    _setStats(
      _stats.copyWith(
        hasRemoteAudio: false,
        clearConnectedAt: true,
        clearMetrics: true,
      ),
    );
    _setState(finalState);
  }

  /// Re-announces `viewer.ready` to the known publisher so it re-offers, nudging
  /// a stalled connection to recover. Used by the background notification's
  /// "Reconnect" action. No-op if no publisher has been seen yet.
  Future<void> reconnect() async {
    final publisher = _publisherId;
    if (publisher == null) return;
    sonicLog('WebRTC', 'manual reconnect -> viewer.ready to=$publisher');
    _emit(SignalingMessageType.viewerReady, const {}, to: publisher);
  }

  /// Tears down the active peer connection and audio when the viewer leaves,
  /// keeping the service reusable for a later session.
  Future<void> leave() => _teardown(ListenerConnectionState.disconnected);

  /// Tears down the peer connection and audio and releases all streams.
  Future<void> dispose() async {
    _stopStatsPolling();
    await _disposePeerConnection();
    await _audioReceiver.stop();
    await _connectionStateController.close();
    await _statsController.close();
    await _outboundController.close();
  }
}
