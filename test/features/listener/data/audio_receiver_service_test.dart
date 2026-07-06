import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/webrtc/rtc_peer_connection_factory.dart';
import 'package:sonic_relay/features/listener/data/audio_receiver_service.dart';

class FakeRtcMediaStream implements RtcMediaStream {
  FakeRtcMediaStream(this.id);

  @override
  final String id;

  bool? audioEnabled;

  @override
  Future<void> setAudioEnabled(bool enabled) async => audioEnabled = enabled;
}

void main() {
  late WebRtcAudioReceiverService service;

  setUp(() => service = WebRtcAudioReceiverService());

  test('play enables the stream audio and marks playing', () async {
    final stream = FakeRtcMediaStream('stream-1');

    await service.play(stream);

    expect(stream.audioEnabled, isTrue);
    expect(service.isPlaying, isTrue);
  });

  test('stop disables the current stream and clears playing', () async {
    final stream = FakeRtcMediaStream('stream-1');
    await service.play(stream);

    await service.stop();

    expect(stream.audioEnabled, isFalse);
    expect(service.isPlaying, isFalse);
  });

  test('replacing a stream disables the previous one', () async {
    final first = FakeRtcMediaStream('stream-1');
    final second = FakeRtcMediaStream('stream-2');

    await service.play(first);
    await service.play(second);

    expect(first.audioEnabled, isFalse);
    expect(second.audioEnabled, isTrue);
    expect(service.isPlaying, isTrue);
  });
}
