import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/webrtc/rtc_peer_connection_factory.dart';

void main() {
  group('RtcSessionDescription', () {
    test('parses a flat offer payload and round-trips', () {
      final desc = RtcSessionDescription.fromSignalingPayload({
        'sdp': 'v=0...',
        'type': 'offer',
      });

      expect(desc.sdp, 'v=0...');
      expect(desc.type, 'offer');
      expect(desc.toSignalingPayload(), {'sdp': 'v=0...', 'type': 'offer'});
    });

    test('parses a nested sdp payload', () {
      final desc = RtcSessionDescription.fromSignalingPayload({
        'sdp': {'sdp': 'v=0-nested', 'type': 'offer'},
      });

      expect(desc.sdp, 'v=0-nested');
      expect(desc.type, 'offer');
    });

    test('defaults type to offer for a partial payload', () {
      final desc = RtcSessionDescription.fromSignalingPayload({});
      expect(desc.sdp, '');
      expect(desc.type, 'offer');
    });
  });

  group('RtcIceCandidate', () {
    test('parses a flat candidate payload and round-trips', () {
      final candidate = RtcIceCandidate.fromSignalingPayload({
        'candidate': 'candidate:1 1 udp ...',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });

      expect(candidate.candidate, 'candidate:1 1 udp ...');
      expect(candidate.sdpMid, '0');
      expect(candidate.sdpMLineIndex, 0);
      expect(candidate.toSignalingPayload(), {
        'candidate': 'candidate:1 1 udp ...',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    test('parses a nested candidate payload and numeric line index', () {
      final candidate = RtcIceCandidate.fromSignalingPayload({
        'candidate': {
          'candidate': 'candidate:2 ...',
          'sdpMid': 'audio',
          'sdpMLineIndex': 1.0,
        },
      });

      expect(candidate.candidate, 'candidate:2 ...');
      expect(candidate.sdpMid, 'audio');
      expect(candidate.sdpMLineIndex, 1);
    });

    test('tolerates a partial payload', () {
      final candidate = RtcIceCandidate.fromSignalingPayload({});
      expect(candidate.candidate, '');
      expect(candidate.sdpMid, isNull);
      expect(candidate.sdpMLineIndex, isNull);
    });

    test('exposes a non-null sdpMid for the native WebRTC layer', () {
      // Android's libwebrtc aborts the process (SIGABRT) if addIceCandidate
      // receives a null sdpMid, so a mid-less candidate must coalesce to ''.
      const withMid = RtcIceCandidate(
        candidate: 'c',
        sdpMid: '0',
        sdpMLineIndex: 0,
      );
      const withoutMid = RtcIceCandidate(candidate: 'c', sdpMLineIndex: 0);

      expect(withMid.nativeSafeSdpMid, '0');
      expect(withoutMid.nativeSafeSdpMid, '');
    });
  });
}
