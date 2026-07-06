/// Coarse, display-only statistics for the audio session. Never carries SDP
/// or ICE candidate bodies — only high-level state labels and flags.
class ListenerStats {
  const ListenerStats({
    this.iceState = 'Idle',
    this.hasRemoteAudio = false,
    this.connectedAt,
  });

  const ListenerStats.initial() : this();

  final String iceState;
  final bool hasRemoteAudio;
  final DateTime? connectedAt;

  ListenerStats copyWith({
    String? iceState,
    bool? hasRemoteAudio,
    DateTime? connectedAt,
    bool clearConnectedAt = false,
  }) {
    return ListenerStats(
      iceState: iceState ?? this.iceState,
      hasRemoteAudio: hasRemoteAudio ?? this.hasRemoteAudio,
      connectedAt: clearConnectedAt ? null : (connectedAt ?? this.connectedAt),
    );
  }
}
