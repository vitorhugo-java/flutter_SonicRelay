# SonicRelay Flutter Viewer

Mobile viewer for the low-latency SonicRelay audio streaming suite.

- [Backend](https://github.com/vitorhugo-java/dotnet_SonicRelay)
- [Windows publisher](https://github.com/vitorhugo-java/windows_SonicRelay)

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

## Session join flow

An authenticated viewer enters the temporary code shown by the Windows publisher on `/join`. The app trims and normalizes the code to uppercase, validates its shape locally, and requires the backend-issued viewer device UUID before sending:

```json
{
  "code": "ABC123",
  "deviceId": "viewer_device_uuid"
}
```

The authenticated Dio client calls `POST /api/sessions/join`. A successful response contains `sessionId`, the `viewer` role, and a `ws` or `wss` `signalingUrl`. This context is kept in memory for signaling; it is not persisted. The app then opens `/session/waiting`, where it displays the prepared connection context until a later signaling feature connects the stream.

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

After a successful `POST /api/sessions/join`, the viewer opens an authenticated WebSocket connection to the returned `signalingUrl`, with `sessionId` and the viewer's `deviceId` appended as query parameters and the current access token sent as a bearer header:

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
- `SignalingClient` builds the authenticated connection URL from the joined session context, sends `viewer.ready` once the socket opens, replies to `ping` with `pong`, maps every frame through `SignalingMessageMapper` into a typed `SignalingMessage`, and closes the socket (without reconnecting) when it receives `session.ended` or the viewer explicitly leaves.

Transport (`lib/core/websocket`) and signaling (`lib/features/signaling`) never log SDP or ICE candidate payload bodies.

## WebRTC audio viewer

The Flutter app is the WebRTC **viewer**: it only ever receives a remote audio track. It never captures a microphone, never adds a local track, and never handles video. Media flows peer-to-peer (or through coturn when required) directly between the Windows publisher and the viewer — the backend routes only the signaling envelopes, never the media.

Negotiation runs entirely over the signaling socket described above:

1. `SignalingClient` sends `viewer.ready` once the socket opens.
2. On `webrtc.offer`, the viewer creates an `RTCPeerConnection`, applies the remote description, creates an answer, sets the local description, and sends `webrtc.answer`.
3. Local ICE candidates are sent as `webrtc.ice_candidate`; remote candidates are applied as they arrive (candidates received before the offer are buffered and flushed once the remote description is set).
4. The remote audio track is played through the device's audio output.
5. The peer connection and audio are torn down explicitly on `session.ended`, when the viewer leaves, or when the view model is disposed.

Responsibilities are split across the standard FDD boundaries:

- `lib/core/webrtc` holds reusable, platform-facing adapters: `RtcIceServerConfig` (ICE/STUN/TURN configuration) and `RtcPeerConnectionFactory` (a thin, testable wrapper over `flutter_webrtc`). No private/production TURN credentials are embedded; the MVP default is a single public STUN server, and configuration can later come from `AppConfig` or the backend.
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

## UI preview

The current app provides a dark Material 3 shell with reusable controls, connected token authentication, and a listener dashboard that reflects live WebRTC connection state.

To capture Android screenshots, run an emulator, start the app with `flutter run`, navigate through the local preview actions, and use the emulator screenshot control. Recommended captures are the login screen and the listener dashboard at a common phone size such as 1080 × 2400.
