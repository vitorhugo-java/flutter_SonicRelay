# WebRTC Audio Receiver Design

## Goal

Implement the Flutter viewer's WebRTC audio receiver with `flutter_webrtc` and wire it to the existing signaling client so the app can accept a publisher's offer, answer it, exchange ICE candidates, and play the remote audio track — receive-only, with the backend acting purely as a signaling router and never as a media relay.

## Constraints (from issue #7)

- Feature Driven Development: receiver behavior lives in `lib/features/listener`, reusable WebRTC setup lives in `lib/core/webrtc`.
- Audio only. No video, no microphone capture, no local audio tracks, no `addTrack`. The viewer only ever consumes a remote audio track.
- The backend is not a media relay: media flows peer-to-peer (or via coturn) over WebRTC; only offer/answer/ICE envelopes cross the signaling socket.
- WebRTC lifecycle is explicit and disposable.
- Never log full SDP or full ICE payloads.

## Decisions

- **Thin, testable wrapper layer in `lib/core/webrtc`.** The `flutter_webrtc` types (`RTCPeerConnection`, `RTCSessionDescription`, `RTCIceCandidate`, `MediaStream`) are platform-backed and can't run in unit tests. We hide them behind small domain-neutral abstractions so the receiver/audio services depend on fakeable interfaces, matching the repo's hand-written-fake test style (no mockito/mocktail dependency is added).
  - `RtcSessionDescription` / `RtcIceCandidate` — plain immutable value types with `fromSignalingPayload` / `toSignalingPayload` helpers that define the wire shape of `webrtc.offer|answer|ice_candidate` payloads.
  - `RtcMediaStream` — abstract handle over a remote stream (`id`, `setAudioEnabled`, `dispose`).
  - `RtcPeerConnection` — abstract wrapper exposing exactly what the receiver needs: `setRemoteDescription`, `createAnswer`, `setLocalDescription`, `addIceCandidate`, and callbacks for local ICE candidates, remote stream, and connection-state changes, plus `dispose`.
  - `RtcPeerConnectionFactory` — abstract factory; `FlutterWebRtcPeerConnectionFactory` is the production implementation backed by `createPeerConnection`, and each wrapper method delegates to the real object.
- **ICE configuration is data, not hardcoded secrets.** `RtcIceServerConfig` holds a list of ICE servers and produces the peer-connection `configuration` map. `RtcIceServerConfig.defaults()` uses only a public Google STUN server for the MVP. It can be built from `AppConfig`/backend-provided servers later; no private/production TURN credentials are embedded.
- **Receiver orchestration is signaling-agnostic.** `WebRtcReceiverService` (listener/data) owns the peer-connection lifecycle and negotiation state machine but does **not** import `SignalingClient`. It consumes inbound envelopes via `handleSignal(SignalingMessage)` and emits outbound envelopes on an `outboundSignals` stream (`webrtc.answer`, `webrtc.ice_candidate`). This keeps it unit-testable with plain fakes and avoids a circular provider dependency. The view model bridges the two streams to the signaling client.
- **Audio playback is isolated.** `AudioReceiverService` (`WebRtcAudioReceiverService`) takes the remote `RtcMediaStream`, enables its audio track, and tracks playing state. On native platforms flutter_webrtc routes a received, enabled audio track to the output automatically, so the MVP keeps this deliberately minimal and free of platform static calls (keeps it unit-testable; speaker routing is a documented future enhancement).
- **Explicit negotiation flow** inside `WebRtcReceiverService`:
  1. `viewer.ready` is already sent by `SignalingClient` on connect.
  2. On `webrtc.offer`: create the peer connection from the ICE config, `setRemoteDescription(offer)`, `createAnswer`, `setLocalDescription(answer)`, emit `webrtc.answer`.
  3. On `webrtc.ice_candidate`: `addIceCandidate`.
  4. Local ICE candidates from the wrapper are emitted as `webrtc.ice_candidate`.
  5. Remote stream from the wrapper is handed to `AudioReceiverService`.
  6. `session.ended`/`leave`/`dispose` tears down the peer connection and audio, resetting state.
- **State exposed to UI.** `ListenerConnectionState` (enum: `idle`, `waitingForOffer`, `negotiating`, `connecting`, `connected`, `failed`, `disconnected`) and immutable `ListenerStats` (ICE/peer state label, remote-audio flag, connected-at) are surfaced by `ListenerViewModel` (Riverpod `Notifier`). `ListenerPage` becomes a `ConsumerWidget` rendering real connection state, the ICE state metric, and a working "Leave session" action.
- **Signaling send surface.** `SignalingClient` gains one public `send(type, payload, {to})` method (a thin wrapper over the existing private `_send`) so the view model can forward answers/candidates. No other signaling behavior changes.
- **Logging discipline.** Nothing logs SDP or ICE payload bodies; only coarse types/states are ever surfaced. The design adds no payload logging at all.

## Components and data flow

```
SignalingClient.messages ──▶ ListenerViewModel ──▶ WebRtcReceiverService.handleSignal
                                     ▲                          │
SignalingClient.send    ◀────────────┴──── outboundSignals ◀────┘
                                                                │
                              RtcPeerConnectionFactory ◀────────┤ (create on offer)
                                     │                          │
                              RtcPeerConnection ── remote stream ▶ AudioReceiverService
                                     └── local ICE / conn-state ─▶ state + outbound
```

## Tests

- Unit: `RtcIceServerConfig` default/custom server → configuration map shape.
- Unit: `RtcSessionDescription`/`RtcIceCandidate` payload round-trip and defensive parsing of partial payloads.
- Unit: `WebRtcReceiverService` with a fake factory/peer connection — offer produces `setRemoteDescription` → `createAnswer` → `setLocalDescription` → outbound `webrtc.answer`; inbound `webrtc.ice_candidate` → `addIceCandidate`; local candidate → outbound `webrtc.ice_candidate`; remote stream → audio service `play`; connection-state transitions map to `ListenerConnectionState`.
- Unit: cleanup — `session.ended`/`dispose` disposes the peer connection and stops audio, and a second offer is ignored/renegotiated cleanly.
- Unit: `WebRtcAudioReceiverService` enables audio on play and disables/clears on stop.
- Widget: `ListenerPage` renders idle, connected, and failed states and the leave action.

## Acceptance criteria

- `flutter analyze` exits 0.
- `flutter test` exits 0.
- Offer/answer/ICE flow handled end-to-end through the signaling feature.
- Remote audio track is received and played when paired with a compatible publisher.
- `ListenerViewModel` exposes connection state to the UI.
- No video, microphone capture, or local audio track is introduced; backend remains signaling-only.
- README documents the WebRTC viewer flow.
