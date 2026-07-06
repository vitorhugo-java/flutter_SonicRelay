import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import 'rtc_ice_server_config.dart';

/// Domain-neutral session description (offer/answer) used across the app so
/// higher layers never depend directly on `flutter_webrtc` types.
class RtcSessionDescription {
  const RtcSessionDescription({required this.sdp, required this.type});

  /// Parses a `webrtc.offer`/`webrtc.answer` signaling payload. Tolerates both
  /// a flat `{sdp, type}` shape and a nested `{sdp: {sdp, type}}` shape.
  factory RtcSessionDescription.fromSignalingPayload(
    Map<String, Object?> payload,
  ) {
    final nested = payload['sdp'];
    if (nested is Map) {
      final map = Map<String, Object?>.from(nested);
      return RtcSessionDescription(
        sdp: map['sdp'] as String? ?? '',
        type: map['type'] as String? ?? 'offer',
      );
    }
    return RtcSessionDescription(
      sdp: nested as String? ?? '',
      type: payload['type'] as String? ?? 'offer',
    );
  }

  final String sdp;
  final String type;

  Map<String, Object?> toSignalingPayload() => {'sdp': sdp, 'type': type};
}

/// Domain-neutral ICE candidate.
class RtcIceCandidate {
  const RtcIceCandidate({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  /// Parses a `webrtc.ice_candidate` signaling payload. Tolerates both a flat
  /// shape and a nested `{candidate: {...}}` shape.
  factory RtcIceCandidate.fromSignalingPayload(Map<String, Object?> payload) {
    final source = payload['candidate'] is Map
        ? Map<String, Object?>.from(payload['candidate'] as Map)
        : payload;
    final line = source['sdpMLineIndex'];
    return RtcIceCandidate(
      candidate: source['candidate'] as String? ?? '',
      sdpMid: source['sdpMid'] as String?,
      sdpMLineIndex: line is int ? line : (line as num?)?.toInt(),
    );
  }

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  Map<String, Object?> toSignalingPayload() => {
    'candidate': candidate,
    'sdpMid': sdpMid,
    'sdpMLineIndex': sdpMLineIndex,
  };
}

/// High-level peer-connection lifecycle states, decoupled from
/// `RTCPeerConnectionState`.
enum RtcConnectionState {
  idle,
  connecting,
  connected,
  disconnected,
  failed,
  closed,
}

/// How media is reaching the viewer, derived from the selected ICE candidate
/// pair.
enum RtcTransportMode {
  /// Peer-to-peer (host/srflx/prflx candidates).
  direct,

  /// Relayed through a TURN server.
  relay,

  /// Not yet known (no selected pair / stats unavailable).
  unknown,
}

/// Coarse, display-only connection statistics polled from the peer connection.
/// Carries only numbers and a transport label — never SDP or candidate bodies.
class RtcConnectionStats {
  const RtcConnectionStats({
    this.rttMs,
    this.jitterMs,
    this.transport = RtcTransportMode.unknown,
  });

  /// Estimated round-trip time in milliseconds, when available.
  final double? rttMs;

  /// Inbound audio jitter in milliseconds, when available.
  final double? jitterMs;

  final RtcTransportMode transport;
}

/// A handle over a remote media stream. The viewer only ever consumes audio.
abstract class RtcMediaStream {
  String get id;

  Future<void> setAudioEnabled(bool enabled);
}

/// The subset of a WebRTC peer connection the receiver needs. Abstracted so
/// the receiver logic is unit-testable with a plain fake.
abstract class RtcPeerConnection {
  Future<void> setRemoteDescription(RtcSessionDescription description);

  Future<RtcSessionDescription> createAnswer();

  Future<void> setLocalDescription(RtcSessionDescription description);

  Future<void> addIceCandidate(RtcIceCandidate candidate);

  /// Polls coarse connection statistics (RTT, jitter, transport mode). Returns
  /// `null` when nothing usable is available.
  Future<RtcConnectionStats?> getStats();

  set onIceCandidate(void Function(RtcIceCandidate candidate)? callback);

  set onRemoteStream(void Function(RtcMediaStream stream)? callback);

  set onConnectionState(void Function(RtcConnectionState state)? callback);

  Future<void> dispose();
}

/// Creates [RtcPeerConnection] instances.
abstract class RtcPeerConnectionFactory {
  Future<RtcPeerConnection> create(RtcIceServerConfig iceServers);
}

/// Production factory backed by `flutter_webrtc`.
class FlutterWebRtcPeerConnectionFactory implements RtcPeerConnectionFactory {
  const FlutterWebRtcPeerConnectionFactory();

  @override
  Future<RtcPeerConnection> create(RtcIceServerConfig iceServers) async {
    final connection = await webrtc.createPeerConnection(
      iceServers.toConfiguration(),
    );
    return _FlutterWebRtcPeerConnection(connection);
  }
}

class _FlutterWebRtcMediaStream implements RtcMediaStream {
  _FlutterWebRtcMediaStream(this._stream);

  final webrtc.MediaStream _stream;

  @override
  String get id => _stream.id;

  @override
  Future<void> setAudioEnabled(bool enabled) async {
    for (final track in _stream.getAudioTracks()) {
      track.enabled = enabled;
    }
  }
}

class _FlutterWebRtcPeerConnection implements RtcPeerConnection {
  _FlutterWebRtcPeerConnection(this._connection) {
    _connection.onIceCandidate = (candidate) {
      final callback = _onIceCandidate;
      if (callback == null) return;
      callback(
        RtcIceCandidate(
          candidate: candidate.candidate ?? '',
          sdpMid: candidate.sdpMid,
          sdpMLineIndex: candidate.sdpMLineIndex,
        ),
      );
    };
    _connection.onTrack = (event) {
      if (event.track.kind != 'audio') return;
      if (event.streams.isEmpty) return;
      _emitRemoteStream(event.streams.first);
    };
    _connection.onConnectionState = (state) {
      _onConnectionState?.call(_mapConnectionState(state));
    };
  }

  final webrtc.RTCPeerConnection _connection;

  void Function(RtcIceCandidate candidate)? _onIceCandidate;
  void Function(RtcMediaStream stream)? _onRemoteStream;
  void Function(RtcConnectionState state)? _onConnectionState;
  String? _lastStreamId;

  void _emitRemoteStream(webrtc.MediaStream stream) {
    if (stream.id == _lastStreamId) return;
    _lastStreamId = stream.id;
    _onRemoteStream?.call(_FlutterWebRtcMediaStream(stream));
  }

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
  Future<void> setRemoteDescription(RtcSessionDescription description) {
    return _connection.setRemoteDescription(
      webrtc.RTCSessionDescription(description.sdp, description.type),
    );
  }

  @override
  Future<RtcSessionDescription> createAnswer() async {
    final answer = await _connection.createAnswer({});
    return RtcSessionDescription(
      sdp: answer.sdp ?? '',
      type: answer.type ?? 'answer',
    );
  }

  @override
  Future<void> setLocalDescription(RtcSessionDescription description) {
    return _connection.setLocalDescription(
      webrtc.RTCSessionDescription(description.sdp, description.type),
    );
  }

  @override
  Future<void> addIceCandidate(RtcIceCandidate candidate) {
    return _connection.addCandidate(
      webrtc.RTCIceCandidate(
        candidate.candidate,
        candidate.sdpMid,
        candidate.sdpMLineIndex,
      ),
    );
  }

  @override
  Future<RtcConnectionStats?> getStats() async {
    try {
      final reports = await _connection.getStats();
      Map<Object?, Object?>? selectedPair;
      final candidates = <String, Map<Object?, Object?>>{};
      double? jitterMs;

      for (final report in reports) {
        final values = Map<Object?, Object?>.from(report.values);
        switch (report.type) {
          case 'candidate-pair':
            final nominated = values['nominated'] == true;
            final succeeded = values['state'] == 'succeeded';
            if (nominated || (succeeded && selectedPair == null)) {
              selectedPair = values;
            }
          case 'local-candidate':
          case 'remote-candidate':
            candidates[report.id] = values;
          case 'inbound-rtp':
            final isAudio =
                values['kind'] == 'audio' || values['mediaType'] == 'audio';
            final jitter = values['jitter'];
            if (isAudio && jitter is num) {
              jitterMs = jitter.toDouble() * 1000;
            }
        }
      }

      double? rttMs;
      var transport = RtcTransportMode.unknown;
      if (selectedPair != null) {
        final rtt =
            selectedPair['currentRoundTripTime'] ??
            selectedPair['roundTripTime'];
        if (rtt is num) rttMs = rtt.toDouble() * 1000;

        final localType =
            candidates[selectedPair['localCandidateId']]?['candidateType'];
        final remoteType =
            candidates[selectedPair['remoteCandidateId']]?['candidateType'];
        if (localType == 'relay' || remoteType == 'relay') {
          transport = RtcTransportMode.relay;
        } else if (localType != null || remoteType != null) {
          transport = RtcTransportMode.direct;
        }
      }

      if (rttMs == null &&
          jitterMs == null &&
          transport == RtcTransportMode.unknown) {
        return null;
      }
      return RtcConnectionStats(
        rttMs: rttMs,
        jitterMs: jitterMs,
        transport: transport,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    await _connection.close();
    await _connection.dispose();
  }

  RtcConnectionState _mapConnectionState(
    webrtc.RTCPeerConnectionState state,
  ) => switch (state) {
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateNew =>
      RtcConnectionState.idle,
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnecting =>
      RtcConnectionState.connecting,
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
      RtcConnectionState.connected,
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
      RtcConnectionState.disconnected,
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
      RtcConnectionState.failed,
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
      RtcConnectionState.closed,
  };
}
