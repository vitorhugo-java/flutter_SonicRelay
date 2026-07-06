# Listener Status & Session Lifecycle UI — Implementation Plan

Spec: `docs/superpowers/specs/2026-07-06-listener-status-lifecycle-design.md`
Issue: #8

## Step 1 — Core WebRTC stats surface

- `lib/core/webrtc/rtc_peer_connection_factory.dart`
  - Add `enum RtcTransportMode { direct, relay, unknown }`.
  - Add `class RtcConnectionStats { double? rttMs; double? jitterMs; RtcTransportMode transport; }`.
  - Add `Future<RtcConnectionStats?> getStats()` to the `RtcPeerConnection` interface.
  - Implement `getStats()` in `_FlutterWebRtcPeerConnection` by parsing the selected
    `candidate-pair` (RTT + transport from candidate types) and audio `inbound-rtp`
    (jitter); fully defensive, returns `null` on any failure.

## Step 2 — Domain

- `lib/features/listener/domain/listener_connection_state.dart` — add `reconnecting`
  and `ended`.
- `lib/features/listener/domain/listener_stats.dart` — add nullable `rttMs`,
  `jitterMs`, and `transport` (`RtcTransportMode`, default `unknown`); extend
  `copyWith` with a `clearMetrics` flag.

## Step 3 — Receiver service

- `lib/features/listener/data/webrtc_receiver_service.dart`
  - Inject `statsInterval` (default 2s).
  - Add `refreshStats()` + a periodic timer started on `connected`, stopped on every
    teardown / disconnect / dispose.
  - Map WebRTC `disconnected` ⇒ `reconnecting`; `session.ended` ⇒ `_teardown(ended)`;
    `session.left` / leave ⇒ `_teardown(disconnected)`.
  - Reset rtt/jitter/transport on teardown via `clearMetrics`.

## Step 4 — View model

- `lib/features/listener/presentation/listener_view_model.dart`
  - Add `SignalingConnectionState? signaling` to `ListenerState` (+ `copyWith`).
  - Subscribe to `_signaling.connectionState`; cancel in `onDispose`.

## Step 5 — Widgets

- `widgets/audio_visualizer.dart` — animated `AudioVisualizer(active:)`.
- `widgets/ice_state_panel.dart` — `IceStatePanel` (signaling + ICE status rows).
- `widgets/latency_card.dart` — `LatencyCard(rttMs, jitterMs, transport)`.
- `widgets/listen_control_button.dart` — `ListenControlButton(ended, onLeave)`.

## Step 6 — Page

- Rewrite `listener_page.dart` to compose the widgets and render every state,
  including waiting / reconnecting / ended banners.

## Step 7 — Tests

- Update `test/features/listener/data/webrtc_receiver_service_test.dart` for the new
  terminal states + add `refreshStats` / `leave` coverage.
- Add `test/features/listener/presentation/listener_view_model_test.dart` for leave.
- Rewrite `test/features/listener/presentation/listener_page_test.dart` for all UI
  states.

## Step 8 — Docs & verification

- Document listener states in `README.md`.
- Run `flutter analyze` and `flutter test`; fix until both pass.
