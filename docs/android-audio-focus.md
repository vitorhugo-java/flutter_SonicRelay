# Android audio focus: mixing with other apps (issue #19)

SonicRelay is an **audio-only remote viewer**. Its playback must *mix* with
whatever the device is already playing (Spotify, YouTube Music, podcasts…).
Connecting to or disconnecting from a relay must never pause, resume, or duck
another app's media.

## Why Spotify used to pause

`lib/core/webrtc/rtc_peer_connection_factory.dart` configured flutter_webrtc's
Android audio session with the `AndroidAudioConfiguration.media` preset in two
places (`WebRTC.initialize` and `Helper.setAndroidAudioConfiguration`). In
flutter_webrtc 1.5.x that preset means:

```dart
manageAudioFocus: true,
androidAudioFocusMode: AndroidAudioFocusMode.gain,   // AUDIOFOCUS_GAIN
androidAudioMode: AndroidAudioMode.normal,
androidAudioStreamType: AndroidAudioStreamType.music,
androidAudioAttributesUsageType: AndroidAudioAttributesUsageType.media,
```

`AUDIOFOCUS_GAIN` requests *continuous, exclusive* focus. Well-behaved media
apps respond to the resulting focus loss by pausing (or Android itself fades
them), so starting a relay session silenced the user's music. Disconnecting
then abandoned focus, poking the external player's state again.

## Current configuration

`FlutterWebRtcPeerConnectionFactory.concurrentPlaybackAudioConfiguration`
replaces the preset:

```dart
AndroidAudioConfiguration(
  manageAudioFocus: false,
  androidAudioMode: AndroidAudioMode.normal,
  androidAudioStreamType: AndroidAudioStreamType.music,
  androidAudioAttributesUsageType: AndroidAudioAttributesUsageType.media,
  androidAudioAttributesContentType: AndroidAudioAttributesContentType.music,
)
```

- `manageAudioFocus: false` — flutter_webrtc neither requests nor abandons
  audio focus, so other players never see a focus transition from us. Their
  audio and ours are simply mixed by Android.
- `MODE_NORMAL` + `USAGE_MEDIA` + `STREAM_MUSIC` + `CONTENT_TYPE_MUSIC` —
  preserves the issue #14 fix: playback stays on the media volume stream at
  full quality; the device is never dragged into `MODE_IN_COMMUNICATION`
  (earpiece routing, "phone call" quality for every app, call volume slider).

The same configuration is applied at **both** required points, before the
first `RTCPeerConnection` exists:

1. `WebRTC.initialize(options: {'androidAudioConfiguration': ...})` — the
   native `JavaAudioDeviceModule` bakes these attributes into its playback
   `AudioTrack` when the first factory comes up.
2. `Helper.setAndroidAudioConfiguration(...)` — pins the session's
   `AudioManager` state.

No other code in the app touches audio focus, `MediaSession`, or media keys
(verified by search; the only audio-session configuration lives in this
factory).

`test/core/webrtc/webrtc_audio_configuration_test.dart` locks the
configuration's meaning — including `manageAudioFocus: false` and the fact
that it deliberately differs from the upstream `media` preset — so a
flutter_webrtc bump that changes semantics fails in CI instead of on a phone.

## Fallback if a device misbehaves

If some manufacturer/Android build turns out to misroute audio without focus
management, the agreed fallback is a user-facing setting ("Mix with other
apps' audio", enabled by default) that switches to `gainTransientMayDuck` —
which still ducks the other app and is therefore not the default. This is
intentionally *not* implemented until such a device is actually observed.

## Manual acceptance checklist (needs real hardware)

- [ ] Start music in Spotify, connect to SonicRelay → music keeps playing.
- [ ] Both audio streams are audible simultaneously.
- [ ] Disconnect/reconnect the relay → Spotify's playback state is untouched.
- [ ] Works on speaker, wired headphones, and Bluetooth.
- [ ] Validated on Android 12+.
- [ ] Volume responds on the media channel, not the call channel.
- [ ] Audio quality is unchanged (no muffled/low-quality regression).
