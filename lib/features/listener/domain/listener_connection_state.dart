/// The viewer's high-level audio session state, surfaced to the UI.
enum ListenerConnectionState {
  /// No signaling/peer activity yet.
  idle,

  /// Signaling is connected; waiting for the publisher's `webrtc.offer`.
  waitingForOffer,

  /// An offer arrived and the answer is being produced/exchanged.
  negotiating,

  /// ICE is establishing the media path.
  connecting,

  /// Media path established; remote audio is playing.
  connected,

  /// Negotiation or the peer connection failed.
  failed,

  /// The session ended or the viewer left.
  disconnected,
}
