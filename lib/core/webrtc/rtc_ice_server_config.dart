/// A single ICE server (STUN or TURN) used to establish the peer connection.
class RtcIceServer {
  const RtcIceServer({required this.urls, this.username, this.credential});

  final List<String> urls;
  final String? username;
  final String? credential;

  Map<String, Object?> toMap() => {
    'urls': urls,
    if (username != null) 'username': username,
    if (credential != null) 'credential': credential,
  };
}

/// ICE configuration for the viewer's [RtcPeerConnection].
///
/// Kept as plain data so it can be built from [AppConfig] or a
/// backend-provided server list. The default only uses a public STUN server;
/// no private/production TURN credentials are embedded in the app.
class RtcIceServerConfig {
  const RtcIceServerConfig(this.iceServers);

  /// MVP default: a single public STUN server, no TURN.
  factory RtcIceServerConfig.defaults() => const RtcIceServerConfig([
    RtcIceServer(urls: ['stun:stun.l.google.com:19302']),
  ]);

  final List<RtcIceServer> iceServers;

  /// The `configuration` map passed to `createPeerConnection`. Unified Plan
  /// is requested explicitly so a remote send-only audio track surfaces a
  /// receive-only transceiver without any local track being added.
  Map<String, dynamic> toConfiguration() => {
    'iceServers': iceServers.map((server) => server.toMap()).toList(),
    'sdpSemantics': 'unified-plan',
  };
}
