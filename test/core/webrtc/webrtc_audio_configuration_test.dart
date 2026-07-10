import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sonic_relay/core/webrtc/rtc_peer_connection_factory.dart';

/// Guards the audio profile the receiver factory pushes into flutter_webrtc.
///
/// Two behaviors are locked here, so a dependency bump that changes their
/// meaning fails loudly instead of on a real phone:
///
/// - issue #14: the viewer is receive-only and must run in a *media playback*
///   profile — `MODE_NORMAL` / `USAGE_MEDIA` / `STREAM_MUSIC` — never the
///   call/communication routing that muffles every app's audio.
/// - issue #19: the viewer must *mix* with other apps' media instead of
///   pausing it. The `AndroidAudioConfiguration.media` preset requests
///   continuous exclusive focus (`AUDIOFOCUS_GAIN`), which pauses Spotify and
///   friends on connect; the factory therefore uses its own configuration
///   with `manageAudioFocus: false`.
void main() {
  group('concurrentPlaybackAudioConfiguration (issues #14/#19)', () {
    final map = FlutterWebRtcPeerConnectionFactory
        .concurrentPlaybackAudioConfiguration
        .toMap();

    test('does not manage audio focus, so other media keeps playing', () {
      expect(map['manageAudioFocus'], isFalse);
    });

    test('uses MODE_NORMAL, not a call/communication mode', () {
      expect(map['androidAudioMode'], AndroidAudioMode.normal.name);
      expect(
        map['androidAudioMode'],
        isNot(AndroidAudioMode.inCommunication.name),
      );
      expect(map['androidAudioMode'], isNot(AndroidAudioMode.inCall.name));
    });

    test('routes as media, not voice communication', () {
      expect(
        map['androidAudioAttributesUsageType'],
        AndroidAudioAttributesUsageType.media.name,
      );
      expect(
        map['androidAudioAttributesUsageType'],
        isNot(AndroidAudioAttributesUsageType.voiceCommunication.name),
      );
    });

    test('requests the music stream, not the voice-call stream', () {
      expect(map['androidAudioStreamType'], AndroidAudioStreamType.music.name);
      expect(
        map['androidAudioStreamType'],
        isNot(AndroidAudioStreamType.voiceCall.name),
      );
    });

    test('marks content as music for the platform mixer', () {
      expect(
        map['androidAudioAttributesContentType'],
        AndroidAudioAttributesContentType.music.name,
      );
    });

    test(
      'differs from the media preset exactly by not taking audio focus',
      () {
        // The preset pauses other players via AUDIOFOCUS_GAIN (issue #19); if a
        // future flutter_webrtc makes the preset stop managing focus, this
        // custom configuration can be reconsidered.
        final preset = AndroidAudioConfiguration.media.toMap();
        expect(preset['manageAudioFocus'], isTrue);
        expect(map['manageAudioFocus'], isFalse);
      },
    );
  });
}
