# Listener Status & Session Lifecycle UI Design

## Goal

Turn the placeholder listener screen into a polished, useful audio-monitor UI that
surfaces the full lifecycle of a viewer session: signaling status, WebRTC ICE
status, estimated RTT, jitter, transport mode (direct/relay/unknown), and the
distinct waiting / reconnecting / ended states — plus a leave action that tears
down both the peer connection and the signaling socket.

## Constraints (from issue #8)

- Feature Driven Development: all listener UI stays inside `lib/features/listener`.
- Show signaling status, WebRTC ICE status, estimated RTT (when available),
  jitter (when available), transport mode (direct/relay/unknown, when available),
  waiting-publisher, reconnecting, and ended states.
- A leave-session action that closes signaling and disposes the peer connection.
- `flutter analyze` and `flutter test` pass.
- README documents listener states.
- Never surface SDP or ICE candidate bodies — only coarse labels/metrics.

## Decisions

- **RTT / jitter / transport come from a periodic WebRTC stats poll.** The
  `RtcPeerConnection` abstraction gains `Future<RtcConnectionStats?> getStats()`.
  `WebRtcReceiverService` starts a `Timer.periodic` (interval injectable, default
  2s) when the peer connection reaches `connected`, and stops it on any teardown.
  Each tick reads `getStats()` and folds `rttMs` / `jitterMs` / `transport` into
  `ListenerStats`. The poll is driven through a public `refreshStats()` method so
  it is unit-testable without a real timer.
  - `RtcConnectionStats` and `RtcTransportMode { direct, relay, unknown }` live in
    `lib/core/webrtc` (core, never imports features). The production
    `FlutterWebRtcPeerConnection.getStats()` parses the selected `candidate-pair`
    (RTT via `currentRoundTripTime`, transport from the local/remote candidate
    types — `relay` on either side ⇒ relay) and the audio `inbound-rtp` report
    (jitter). Parsing is fully defensive and returns `null` on any error, so a
    device without usable stats simply shows "—".
- **`ListenerConnectionState` gains `reconnecting` and `ended`.** WebRTC
  `disconnected` (transient, may recover) maps to `reconnecting`; a `session.ended`
  signal maps to the terminal `ended`; a viewer-initiated leave / `session.left`
  maps to `disconnected`; `closed` maps to `disconnected`. This lets the UI tell
  "we're trying to recover" apart from "the publisher ended the stream."
- **`ListenerStats` gains nullable `rttMs`, `jitterMs`, and `transport`**
  (`RtcTransportMode`, default `unknown`), reset on teardown. Existing
  `iceState` / `hasRemoteAudio` / `connectedAt` are unchanged.
- **Signaling status is folded into the listener view model.**
  `ListenerViewModel` already holds the `SignalingClient`; it now also subscribes
  to `signaling.connectionState` and exposes a nullable
  `SignalingConnectionState` on `ListenerState`. This keeps the page backed by a
  single provider (the widget tests stub only `listenerViewModelProvider`) rather
  than composing a second one.
- **UI is decomposed into the reusable widgets the issue names**, all under
  `lib/features/listener/presentation/widgets`:
  - `AudioVisualizer` — animated equalizer bars (animate while receiving audio,
    dim and static otherwise), extracted from the old inline visualizer.
  - `IceStatePanel` — a card listing signaling status and ICE status as coloured
    status rows.
  - `LatencyCard` — RTT, jitter, and a transport-mode chip; each metric shows "—"
    when unavailable.
  - `ListenControlButton` — the leave action; its label is state-aware
    ("Leave session" while live, "Back to sessions" once ended).
  - `ListenerPage` composes a connection badge, a state banner (waiting /
    reconnecting / ended messaging), the visualizer, the ICE panel, the latency
    card, an audio metric, and the control button.

## Components and data flow

```
SignalingClient.connectionState ─▶ ListenerViewModel ─▶ ListenerState.signaling
WebRtcReceiverService.connectionState ─▶ ListenerState.connection
WebRtcReceiverService.stats ──────────▶ ListenerState.stats (ice/rtt/jitter/transport)
        ▲ Timer.periodic → refreshStats() → RtcPeerConnection.getStats()

ListenerPage ─ leave ─▶ ListenerViewModel.leave()
                          ├─ WebRtcReceiverService.leave()  (dispose peer + stop audio)
                          └─ SignalingClient.leave()        (close socket)
```

## Tests

- Unit: `WebRtcReceiverService` — `session.ended` ⇒ `ended`; WebRTC `disconnected`
  ⇒ `reconnecting`; `refreshStats()` folds a fake `RtcConnectionStats` (rtt/jitter/
  transport) into `statsValue`; `leave()` disposes the peer connection and stops
  audio (existing transition tests updated for the new terminal states).
- Unit: `ListenerViewModel.leave()` closes the signaling socket and tears down the
  receiver (real services over fake WebSocket + fake peer-connection factory).
- Widget: `ListenerPage` renders idle, waiting-for-publisher, connected (with RTT/
  jitter/transport), reconnecting, ended, and failed states, and the leave action.

## Acceptance criteria

- `flutter analyze` exits 0.
- `flutter test` exits 0.
- Listener screen shows signaling status, ICE status, RTT, jitter, transport mode,
  and the waiting / reconnecting / ended states.
- Leave action closes signaling and disposes the peer connection.
- README documents the listener states.
