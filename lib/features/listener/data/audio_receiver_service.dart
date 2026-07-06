import '../../../core/webrtc/rtc_peer_connection_factory.dart';

/// Plays the remote audio track received over WebRTC. The viewer is
/// receive-only: it never captures a microphone or adds a local track.
abstract class AudioReceiverService {
  /// Starts playing [stream]'s audio. Replacing a currently playing stream
  /// stops the previous one first.
  Future<void> play(RtcMediaStream stream);

  /// Stops playback and disables the current stream's audio.
  Future<void> stop();

  bool get isPlaying;
}

/// Default implementation backed by an [RtcMediaStream].
///
/// On native platforms flutter_webrtc routes a received, enabled remote audio
/// track to the output device automatically, so this deliberately only manages
/// the track's enabled state and the playing flag for the MVP.
class WebRtcAudioReceiverService implements AudioReceiverService {
  RtcMediaStream? _current;
  bool _isPlaying = false;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Future<void> play(RtcMediaStream stream) async {
    if (_current != null && _current!.id != stream.id) {
      await _current!.setAudioEnabled(false);
    }
    _current = stream;
    await stream.setAudioEnabled(true);
    _isPlaying = true;
  }

  @override
  Future<void> stop() async {
    final current = _current;
    _current = null;
    _isPlaying = false;
    if (current != null) {
      await current.setAudioEnabled(false);
    }
  }
}
