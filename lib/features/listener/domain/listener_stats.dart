import '../../../core/webrtc/rtc_peer_connection_factory.dart';

/// Coarse, display-only statistics for the audio session. Never carries SDP
/// or ICE candidate bodies — only high-level state labels, flags, and metrics.
///
/// Interval metrics (loss %, concealment %, average jitter-buffer delay) are
/// derived by the receiver service from deltas between successive stats polls
/// (windows_SonicRelay issue #31 companion), so they describe the *recent*
/// network behavior instead of a lifetime average.
class ListenerStats {
  const ListenerStats({
    this.iceState = 'Idle',
    this.hasRemoteAudio = false,
    this.connectedAt,
    this.rttMs,
    this.jitterMs,
    this.transport = RtcTransportMode.unknown,
    this.packetLossPercent,
    this.concealmentPercent,
    this.jitterBufferDelayMs,
    this.packetsReceived,
    this.packetsLost,
    this.packetsDiscarded,
    this.fecPacketsReceived,
    this.concealmentEvents,
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

  /// Network packet loss over the last stats interval:
  /// `ΔpacketsLost / (ΔpacketsReceived + ΔpacketsLost) * 100`.
  final double? packetLossPercent;

  /// Share of played samples the decoder had to conceal over the last
  /// interval: `ΔconcealedSamples / ΔtotalSamplesReceived * 100`.
  final double? concealmentPercent;

  /// Average time audio spent in the jitter buffer over the last interval:
  /// `ΔjitterBufferDelay / ΔjitterBufferEmittedCount * 1000`.
  final double? jitterBufferDelayMs;

  /// Cumulative counters since the connection started.
  final int? packetsReceived;
  final int? packetsLost;
  final int? packetsDiscarded;
  final int? fecPacketsReceived;
  final int? concealmentEvents;

  ListenerStats copyWith({
    String? iceState,
    bool? hasRemoteAudio,
    DateTime? connectedAt,
    bool clearConnectedAt = false,
    double? rttMs,
    double? jitterMs,
    RtcTransportMode? transport,
    double? packetLossPercent,
    double? concealmentPercent,
    double? jitterBufferDelayMs,
    int? packetsReceived,
    int? packetsLost,
    int? packetsDiscarded,
    int? fecPacketsReceived,
    int? concealmentEvents,
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
      packetLossPercent: clearMetrics
          ? null
          : (packetLossPercent ?? this.packetLossPercent),
      concealmentPercent: clearMetrics
          ? null
          : (concealmentPercent ?? this.concealmentPercent),
      jitterBufferDelayMs: clearMetrics
          ? null
          : (jitterBufferDelayMs ?? this.jitterBufferDelayMs),
      packetsReceived: clearMetrics
          ? null
          : (packetsReceived ?? this.packetsReceived),
      packetsLost: clearMetrics ? null : (packetsLost ?? this.packetsLost),
      packetsDiscarded: clearMetrics
          ? null
          : (packetsDiscarded ?? this.packetsDiscarded),
      fecPacketsReceived: clearMetrics
          ? null
          : (fecPacketsReceived ?? this.fecPacketsReceived),
      concealmentEvents: clearMetrics
          ? null
          : (concealmentEvents ?? this.concealmentEvents),
    );
  }
}
