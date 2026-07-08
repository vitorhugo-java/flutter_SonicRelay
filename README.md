# SonicRelay Flutter Viewer

Mobile viewer for the low-latency SonicRelay audio streaming suite.

- [Backend](https://github.com/vitorhugo-java/dotnet_SonicRelay)
- [Windows publisher](https://github.com/vitorhugo-java/windows_SonicRelay)

Integration docs:

- [Flutter architecture](docs/flutter-architecture.md)
- [Integration flow](docs/integration-flow.md) — the verified end-to-end contract
- [Troubleshooting](docs/troubleshooting.md)

## Architecture

The app uses Feature Driven Development:

- `lib/app`: bootstrap, router, theme, environment configuration, and dependency providers.
- `lib/core`: reusable technical infrastructure such as HTTP, secure storage, WebSocket, and WebRTC adapters.
- `lib/features`: user-facing capabilities. Each feature owns its `data`, `domain`, and `presentation` boundaries when applicable.

Riverpod provides state and dependency composition, go_router handles guarded navigation, Dio provides HTTP infrastructure, and sensitive tokens are stored only through a flutter_secure_storage-backed abstraction. The viewer receives audio over WebRTC (`flutter_webrtc`); the backend only handles auth, sessions, and signaling and is never a media relay.

## Local development

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Override the local backend endpoints with dart defines:

```sh
flutter run \
  --dart-define=SONIC_RELAY_API_URL=https://api.example.com \
  --dart-define=SONIC_RELAY_WS_URL=wss://api.example.com
```

Routes are `/login`, `/join`, `/session/waiting`, `/listener`, and `/settings`. All routes except `/login` are protected; startup restores a stored session before deciding which route to show.

## Continuous integration

`.github/workflows/flutter-ci.yml` runs on every push and pull request to `main`. It pins Flutter `3.38.1` (stable) via [`subosito/flutter-action`](https://github.com/subosito/flutter-action) with dependency caching, and splits the work into three independent jobs so a red job can be retried on its own:

| Job | Command |
| --- | --- |
| `analyze` | `flutter analyze` |
| `test` | `flutter test` |
| `build-android` | `flutter build apk --release`, then uploads `app-release.apk` as an artifact |

The release build signs with the debug keys (see `android/app/build.gradle.kts`), so CI needs **no signing keys and no secrets**. No app-store deployment happens here.

Run the same checks locally before pushing:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## Session join flow

An authenticated viewer enters the temporary code shown by the Windows publisher on `/join`. The app trims and normalizes the code to uppercase, validates its shape locally, and requires the backend-issued viewer device UUID before sending:

```json
{
  "code": "ABC123",
  "deviceId": "viewer_device_uuid"
}
```

The authenticated Dio client calls `POST /api/sessions/join`. The backend responds with the full session record — `{ id, ownerUserId, sourceDeviceId, status, maxViewers, codeExpiresAt, startedAt, endedAt, createdAt, code }`. The response does **not** carry a signaling URL: the client reads `id` as the session id and builds the signaling URL itself from `SONIC_RELAY_WS_URL` + `/ws/signaling`. This context is kept in memory for signaling; it is not persisted. The app then opens `/session/waiting`, where it displays the prepared connection context until a later signaling feature connects the stream.

Invalid or expired codes and full sessions show specific messages. Network failures can be retried, and an unauthorized response clears the authenticated UI state so the router returns to `/login`.

## Backend authentication contract

The configured API must expose:

```text
POST /auth/register
POST /auth/login
POST /auth/refresh
POST /auth/logout
GET  /auth/me
```

Login uses the ASP.NET Identity bearer-token contract. Access and refresh tokens are persisted through `TokenStorage` backed by `flutter_secure_storage`; they are never written to SharedPreferences or logs. A `401` response triggers one refresh attempt and retries the original request. If refresh fails, local tokens are cleared and the app returns to `/login`.

`SONIC_RELAY_API_URL` is required for a deployed backend. The localhost value in `AppConfig` is intended only for local development; production URLs are not embedded in the app.

## Device registration

After an authenticated session is restored or created, the app registers the installation through the authenticated HTTP client as type `flutter_viewer` and platform `android` or `ios`. The backend-issued device UUID is stored separately from auth tokens through a secure-storage-backed `DeviceIdStorage`; the human-readable device name is never used as an identifier.

On later launches, the app validates the stored UUID with `GET /api/devices/{deviceId}` and reuses an active record. A missing or revoked record is replaced through `POST /api/devices`, and the new UUID is persisted for future session join and WebSocket signaling. Settings uses `GET /api/devices` to show the account's registered devices and registration errors without invalidating the authenticated session.

Required device endpoints:

```text
POST /api/devices
GET  /api/devices
GET  /api/devices/{deviceId}
```

## WebSocket signaling contract

After a successful `POST /api/sessions/join`, the viewer opens an authenticated WebSocket connection to `<SONIC_RELAY_WS_URL>/ws/signaling`, with `sessionId` and the viewer's `deviceId` appended as query parameters and the current access token sent as a bearer header:

```text
GET /ws/signaling?sessionId={sessionId}&deviceId={deviceId}
Authorization: Bearer <access_token>
```

Every frame is a typed JSON envelope:

```json
{
  "type": "webrtc.offer",
  "messageId": "uuid",
  "sessionId": "session_uuid",
  "from": "participant_uuid",
  "to": "participant_uuid",
  "timestamp": "2026-07-03T14:00:00-03:00",
  "payload": {}
}
```

Supported `type` values: `session.joined`, `session.left`, `publisher.ready`, `viewer.ready`, `webrtc.offer`, `webrtc.answer`, `webrtc.ice_candidate`, `session.ended`, `error`, `ping`, `pong`. Unrecognized values are mapped to an `unknown` type and still routed to listeners instead of being dropped, so the transport tolerates future message types.

Transport (`lib/core/websocket`) and signaling (`lib/features/signaling`) are split by responsibility:

- `WebSocketClient` is a reusable, reconnecting JSON-over-WebSocket transport with exponential backoff. It carries no knowledge of the signaling schema.
- `SignalingClient` builds the authenticated connection URL from the joined session context, replies to `ping` with `pong`, maps every frame through `SignalingMessageMapper` into a typed `SignalingMessage`, forwards outbound messages (each addressed to a participant via `to`), and closes the socket (without reconnecting) when it receives `session.ended` or the viewer explicitly leaves. `viewer.ready` is **not** sent on connect — it is a routed message the backend rejects without a `to` recipient, so it is sent in reply to `publisher.ready`, addressed to that message's `from` participant.

Transport (`lib/core/websocket`) and signaling (`lib/features/signaling`) never log SDP or ICE candidate payload bodies.

## WebRTC audio viewer

The Flutter app is the WebRTC **viewer**: it only ever receives a remote audio track. It never captures a microphone, never adds a local track, and never handles video. Media flows peer-to-peer (or through coturn when required) directly between the Windows publisher and the viewer — the backend routes only the signaling envelopes, never the media.

Negotiation runs entirely over the signaling socket described above:

1. On `publisher.ready`, the viewer learns the publisher's participant id from the authenticated `from` field and replies `viewer.ready` addressed to it, prompting the publisher to create its peer connection and send the offer.
2. On `webrtc.offer`, the viewer creates an `RTCPeerConnection`, applies the remote description, creates an answer, sets the local description, and sends `webrtc.answer`.
3. Local ICE candidates are sent as `webrtc.ice_candidate`; remote candidates are applied as they arrive (candidates received before the offer are buffered and flushed once the remote description is set).
4. The remote audio track is played through the device's audio output.
5. The peer connection and audio are torn down explicitly on `session.ended`, when the viewer leaves, or when the view model is disposed.

Responsibilities are split across the standard FDD boundaries:

- `lib/core/webrtc` holds reusable, platform-facing adapters: `RtcIceServerConfig` (ICE/STUN/TURN configuration), `IceServersApi`/`IceServersRepository` (fetch and cache ICE servers from the authenticated backend `GET /api/webrtc/ice-servers`, which serves the SonicRelay coturn deployment with short-lived TURN credentials), and `RtcPeerConnectionFactory` (a thin, testable wrapper over `flutter_webrtc`). No private/production TURN credentials are embedded in the app; `RtcIceServerConfig.defaults()` is a public-STUN-only fallback used solely when the backend request fails in a debug build.
- `lib/features/listener/data` holds `WebRtcReceiverService` (the receive-only peer-connection state machine, signaling-agnostic via `handleSignal`/`outboundSignals`) and `AudioReceiverService` (remote audio playback).
- `lib/features/listener/presentation` holds `ListenerViewModel`, which bridges `SignalingClient` and `WebRtcReceiverService` and exposes `ListenerConnectionState` and coarse `ListenerStats` to `ListenerPage`.

SDP and ICE candidate payload bodies are never logged anywhere in the receiver.

## Listener screen states

`ListenerPage` (`lib/features/listener/presentation`) is the viewer's audio monitor. It surfaces the full session lifecycle from a single Riverpod view model that combines the signaling socket status and the WebRTC connection state, and it exposes a leave action that closes signaling and disposes the peer connection.

The screen shows, at a glance:

- **Signaling status** — the WebSocket signaling connection (`Idle`, `Connecting`, `Connected`, `Reconnecting`, `Ended`, `Disconnected`).
- **WebRTC / ICE status** — the peer-connection/ICE state label.
- **Estimated latency (RTT)** and **jitter** — polled from the peer connection's stats roughly every two seconds while connected; each shows `—` until a value is available.
- **Transport mode** — `Direct`, `Relay`, or `Unknown`, derived from the selected ICE candidate pair (relay on either side ⇒ relayed through TURN).

`ListenerConnectionState` drives the headline badge and a contextual banner:

| State | Meaning | UI |
| --- | --- | --- |
| `idle` | No signaling/peer activity yet | "Not connected" |
| `waitingForOffer` | Signaling up; waiting for the publisher's offer | "Waiting for publisher" + waiting banner |
| `negotiating` | Offer received, exchanging the answer | "Negotiating" |
| `connecting` | ICE is establishing the media path | "Connecting" |
| `connected` | Remote audio is playing | "Listening" + animated visualizer |
| `reconnecting` | Media path dropped transiently, trying to recover | "Reconnecting" + reconnect banner |
| `failed` | Negotiation or the peer connection failed | "Connection failed" + error banner |
| `ended` | The publisher ended the stream (terminal) | "Session ended" + banner, "Back to sessions" action |
| `disconnected` | The viewer left or the connection closed cleanly | "Disconnected" |

The presentation layer is composed from small reusable widgets under `lib/features/listener/presentation/widgets`: `AudioVisualizer`, `IceStatePanel`, `LatencyCard`, and `ListenControlButton`. As everywhere else in the receiver, only coarse labels and metrics are surfaced — never SDP or ICE candidate bodies.

## Background playback (Android)

While a stream is active, SonicRelay keeps receiving and playing audio when the app is backgrounded or the screen is locked, using an Android **`mediaPlayback` foreground service** with a persistent notification (issue #13). The WebRTC receiver and signaling client are provider-owned and already outlive the widget tree, so the connection survives the UI being paused; the foreground service adds the process-survival layer Android requires.

- **Feature slice** `lib/features/background`:
  - `ForegroundStreamService` — abstraction over the native service. `AndroidForegroundStreamServiceBridge` talks to the Kotlin `SonicRelayForegroundService` over the `sonicrelay/foreground` method channel and receives notification-button taps (`open`/`stop`/`reconnect`) over the `sonicrelay/foreground/events` event channel. Every other platform uses `NoopForegroundStreamService`.
  - `StreamLifecycleController` — the pure, unit-tested decision core. It starts the service when the app is backgrounded during an active stream (and the setting is on), updates the notification as the connection state changes, stops it on return to foreground / stream end / logout, and enforces a **bounded** background reconnect window (default 45s) after which it stops the service and shows a "stream ended" notice.
- **Notification actions:** Open (focus the app), Stop (leave the session), and Reconnect (while reconnecting).
- **Setting:** `Settings → Playback → Keep audio playing in background` (persisted, on by default). It only has any effect while a stream the user started is active.
- **Manifest:** declares the `mediaPlayback` service and the `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, and `POST_NOTIFICATIONS` permissions. The service is never started from `BOOT_COMPLETED`. No token/session data is ever placed in notifications, intents, logs, or plain storage.

### Manual QA (Android 13/14/15)

1. Join a stream, lock the phone → audio continues; a persistent notification is shown.
2. Switch to another app → audio continues.
3. Notification **Open** → returns to the live session with the correct state.
4. Notification **Stop** → leaves the session and the service stops.
5. Drop Wi-Fi briefly → "reconnecting" notification; restore → recovers. Leave it off past the window → service stops with a "stream ended" notice.
6. Log out while streaming → the service stops.
7. Android 14/15: no `MissingForegroundServiceTypeException` / `SecurityException`.

## UI preview

The current app provides a dark Material 3 shell with reusable controls, connected token authentication, and a listener dashboard that reflects live WebRTC connection state.

To capture Android screenshots, run an emulator, start the app with `flutter run`, navigate through the local preview actions, and use the emulator screenshot control. Recommended captures are the login screen and the listener dashboard at a common phone size such as 1080 × 2400.

## Known limitations

Surfaced during the 2026-07-06 integration pass (see [docs/integration-flow.md](docs/integration-flow.md)):

- **UI does not yet auto-open signaling.** `/session/waiting` shows the prepared connection context, but wiring join → open-signaling → navigate-to-`/listener` into a single UI flow is not done. The signaling and WebRTC layers are complete and unit-tested behind their view models.
- **Windows publisher envelope mismatch.** The current [windows_SonicRelay](https://github.com/vitorhugo-java/windows_SonicRelay) signaling envelope serializes a `viewerId` field and sends `publisher.ready` with no recipient, while the backend routes strictly on `to`/`from` participant UUIDs. Until the publisher aligns with the backend protocol, end-to-end audio will not establish. See [docs/troubleshooting.md](docs/troubleshooting.md).
- **Backend-provided TURN in production.** ICE servers, including short-lived TURN credentials, are fetched from `GET /api/webrtc/ice-servers`. The bundled `RtcIceServerConfig.defaults()` fallback (public STUN only, no TURN) is used only when that request fails and the app is a debug build; strict/symmetric NATs will fail to establish a media path in that fallback path.
- **No live E2E in CI.** Verification is static contract alignment plus `flutter analyze`, `flutter test`, and an Android build — not a live audio session against a running backend and publisher.
