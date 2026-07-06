/// The signaling message types exchanged over `/ws/signaling`.
enum SignalingMessageType {
  sessionJoined('session.joined'),
  sessionLeft('session.left'),
  publisherReady('publisher.ready'),
  viewerReady('viewer.ready'),
  webrtcOffer('webrtc.offer'),
  webrtcAnswer('webrtc.answer'),
  webrtcIceCandidate('webrtc.ice_candidate'),
  sessionEnded('session.ended'),
  error('error'),
  ping('ping'),
  pong('pong'),

  /// Any wire value not covered above. Kept distinct so unrecognized
  /// messages can be forwarded instead of dropped or crashing the client.
  unknown('unknown');

  const SignalingMessageType(this.wireValue);

  final String wireValue;

  static SignalingMessageType fromWireValue(String value) =>
      SignalingMessageType.values.firstWhere(
        (type) => type.wireValue == value,
        orElse: () => SignalingMessageType.unknown,
      );
}
