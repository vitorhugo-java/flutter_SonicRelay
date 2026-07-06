# WebRTC Audio Receiver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a receive-only WebRTC audio receiver in the Flutter viewer using `flutter_webrtc`, integrated with the existing signaling client, so the app answers a publisher's offer, exchanges ICE, and plays remote audio — with the backend used only for signaling.

**Architecture:** Reusable, testable WebRTC wrappers live in `lib/core/webrtc`; the receiver state machine, audio playback, connection state, and UI live in `lib/features/listener`. The receiver service is signaling-agnostic (inbound `handleSignal`, outbound `outboundSignals` stream); the view model bridges it to `SignalingClient`.

**Tech Stack:** Dart, Flutter, Riverpod, flutter_webrtc, flutter_test

---

### Task 1: Core WebRTC wrappers and ICE config

**Files:**
- Create: `lib/core/webrtc/rtc_ice_server_config.dart`
- Create: `lib/core/webrtc/rtc_peer_connection_factory.dart`
- Create: `test/core/webrtc/rtc_ice_server_config_test.dart`
- Create: `test/core/webrtc/rtc_signaling_payload_test.dart`

- [ ] Write tests for `RtcIceServerConfig` (default STUN, custom servers → configuration map) and for `RtcSessionDescription`/`RtcIceCandidate` payload round-trip + partial-payload parsing.
- [ ] Implement `RtcIceServerConfig`, the value types (`RtcSessionDescription`, `RtcIceCandidate`) with signaling-payload helpers, the `RtcMediaStream`/`RtcPeerConnection`/`RtcPeerConnectionFactory` abstractions, and the `FlutterWebRtc*` production implementations backed by `flutter_webrtc`.
- [ ] Run targeted tests; confirm GREEN.

### Task 2: Listener domain

**Files:**
- Create: `lib/features/listener/domain/listener_connection_state.dart`
- Create: `lib/features/listener/domain/listener_stats.dart`

- [ ] Implement `ListenerConnectionState` enum and immutable `ListenerStats` (ICE/peer state label, remote-audio flag, connected-at) with an initial constructor and `copyWith`.

### Task 3: Audio receiver service

**Files:**
- Create: `lib/features/listener/data/audio_receiver_service.dart`
- Create: `test/features/listener/data/audio_receiver_service_test.dart`

- [ ] Write tests: `play` enables the stream's audio and marks playing; `stop` disables/clears; replacing a stream stops the previous one.
- [ ] Implement `AudioReceiverService` interface and `WebRtcAudioReceiverService` over `RtcMediaStream`.
- [ ] Run targeted tests; confirm GREEN.

### Task 4: WebRTC receiver service

**Files:**
- Create: `lib/features/listener/data/webrtc_receiver_service.dart`
- Modify: `lib/features/signaling/data/signaling_client.dart` (add public `send`)
- Create: `test/features/listener/data/webrtc_receiver_service_test.dart`

- [ ] Write tests with fake factory/peer connection/audio service: offer → remote-desc/answer/local-desc + outbound `webrtc.answer`; inbound ICE → `addIceCandidate`; local ICE → outbound `webrtc.ice_candidate`; remote stream → audio `play`; connection-state → `ListenerConnectionState`; `session.ended`/`dispose` tears down peer + audio.
- [ ] Add a public `send(type, payload, {to})` to `SignalingClient` wrapping the existing private `_send`.
- [ ] Implement `WebRtcReceiverService` (state machine, `outboundSignals`, `connectionState`, `stats`, `handleSignal`, `dispose`).
- [ ] Run targeted tests; confirm GREEN.

### Task 5: Presentation and wiring

**Files:**
- Create: `lib/features/listener/presentation/listener_view_model.dart`
- Modify: `lib/features/listener/presentation/listener_page.dart`
- Modify: `lib/app/di/app_providers.dart`
- Create: `test/features/listener/presentation/listener_page_test.dart`

- [ ] Add providers: `rtcIceServerConfigProvider`, `rtcPeerConnectionFactoryProvider`, `audioReceiverServiceProvider`, `webRtcReceiverServiceProvider`.
- [ ] Implement `ListenerViewModel` (Riverpod `Notifier`) bridging `SignalingClient` ↔ `WebRtcReceiverService`, exposing `ListenerConnectionState` + `ListenerStats`, with `leave()`.
- [ ] Rebuild `ListenerPage` as a `ConsumerWidget` rendering real connection state, ICE metric, and a working leave action.
- [ ] Write a widget test for idle/connected/failed render + leave.
- [ ] Run targeted tests; confirm GREEN.

### Task 6: Documentation and acceptance verification

**Files:**
- Modify: `README.md`

- [ ] Document the WebRTC viewer flow (offer/answer/ICE, receive-only audio, backend-not-a-relay, ICE config) in README.
- [ ] Run `flutter analyze`; confirm exit code 0.
- [ ] Run `flutter test`; confirm exit code 0.
- [ ] Review the scoped diff; confirm no video/mic/local-audio-track code and backend stays signaling-only.
- [ ] Commit the scoped files on `main` with `Closes #7`, push `origin/main`, and confirm issue #7 auto-closed.
