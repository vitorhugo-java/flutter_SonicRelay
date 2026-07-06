import '../../../core/webrtc/rtc_peer_connection_factory.dart';

/// Coarse, display-only statistics for the audio session. Never carries SDP
/// or ICE candidate bodies — only high-level state labels, flags, and metrics.
class ListenerStats {
  const ListenerStats({
    this.iceState = 'Idle',
    this.hasRemoteAudio = false,
    this.connectedAt,
    this.rttMs,
    this.jitterMs,
    this.transport = RtcTransportMode.unknown,
  });

  const ListenerStats.initial() : this();

  final String iceState;
  final bool hasRemoteAudio;
  final DateTime? connectedAt;

  /// Estimated round-trip time in milliseconds, when available.
  final double? rttMs;

  /// Inbound audio jitter in milliseconds, when available.
  final double? jitterMs;

  /// How media is reaching the viewer (direct/relay/unknown).
  final RtcTransportMode transport;

  ListenerStats copyWith({
    String? iceState,
    bool? hasRemoteAudio,
    DateTime? connectedAt,
    bool clearConnectedAt = false,
    double? rttMs,
    double? jitterMs,
    RtcTransportMode? transport,
    bool clearMetrics = false,
  }) {
    return ListenerStats(
      iceState: iceState ?? this.iceState,
      hasRemoteAudio: hasRemoteAudio ?? this.hasRemoteAudio,
      connectedAt: clearConnectedAt ? null : (connectedAt ?? this.connectedAt),
      rttMs: clearMetrics ? null : (rttMs ?? this.rttMs),
      jitterMs: clearMetrics ? null : (jitterMs ?? this.jitterMs),
      transport: clearMetrics
          ? RtcTransportMode.unknown
          : (transport ?? this.transport),
    );
  }
}
