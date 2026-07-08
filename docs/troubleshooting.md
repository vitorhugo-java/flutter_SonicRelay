# Troubleshooting

Failure modes seen or reasoned about during the 2026-07-06 integration pass, with
the observable symptom, the cause, and the fix or current status.

## Join fails with "invalid session data"

- **Symptom:** entering a valid code shows *"The server returned invalid session
  data. Please retry."* (`SessionsFailureKind.invalidResponse`).
- **Cause:** the client parsed the join response expecting `sessionId`/`role`/
  `signalingUrl`, but the backend returns a session record (`id`, `status`,
  `code`, …) and no signaling URL.
- **Status:** fixed. `JoinSessionResponse` now reads `id` and the client builds the
  signaling URL from `SONIC_RELAY_WS_URL`.

## Publisher never sends an offer / viewer stuck on "Waiting for publisher"

- **Symptom:** signaling connects, but no `webrtc.offer` ever arrives; the viewer
  stays in `waitingForOffer`.
- **Cause:** the viewer used to send `viewer.ready` with no `to`, immediately on
  socket open. `viewer.ready` is a routed message; the backend rejects it with
  `error: invalid_recipient`, so the publisher never receives a readiness signal
  and never offers.
- **Status:** fixed. `viewer.ready` is now sent in reply to `publisher.ready`,
  addressed to that message's `from` participant.

## End-to-end audio still does not connect — Windows publisher envelope mismatch

- **Symptom:** the viewer joins, opens signaling and replies `viewer.ready`
  correctly, but the publisher does not complete the WebRTC handshake.
- **Cause (cross-repo):** the current
  [windows_SonicRelay](https://github.com/vitorhugo-java/windows_SonicRelay)
  `SignalingMessageEnvelope` serializes a `viewerId` property and sends
  `publisher.ready` with no recipient, while the backend routes strictly on
  `to`/`from` participant UUIDs (see the backend `docs/protocol.md` and
  `SignalingWebSocketEndpoint`). A publisher sending `viewerId` instead of `to`
  will be rejected with `invalid_recipient`, and inbound `from`/`to` will not
  populate the publisher's `ViewerId`.
- **Status:** not fixable in this repo. File/track an issue on
  [windows_SonicRelay](https://github.com/vitorhugo-java/windows_SonicRelay) to
  align its envelope with the backend `to`/`from` participant routing. The Flutter
  viewer is protocol-correct against the backend and will interoperate once the
  publisher is aligned.

## `error` frames from the signaling server

The server sends `{type:"error", payload:{code}}`. Codes and meaning:

| `code` | Meaning | Likely client cause |
| --- | --- | --- |
| `invalid_message` | Not JSON / no `type` | Malformed frame |
| `unsupported_message_type` | `type` not routable | Sending a server-only type |
| `invalid_recipient` | Missing/invalid `to` | Routed message without a participant `to` |
| `participant_not_found` | `to` not in the live session | Stale/incorrect participant id |

## Socket rejected before upgrade

`GET /ws/signaling` returns an HTTP status **before** the WebSocket upgrade when
admission fails:

| Status | Cause |
| --- | --- |
| `400` | `sessionId`/`deviceId` missing or not UUIDs |
| `401` | Missing/invalid bearer token |
| `403` | Device not owned by the user, revoked, or not a participant |
| `404` | Session or device not found |
| `410` | Session ended/expired or past `codeExpiresAt` |

## Publisher unavailable

If the publisher is offline, the viewer joins and signaling connects, but no
`publisher.ready` arrives and no offer follows — the viewer remains in
`waitingForOffer`. This is expected: the UI shows the "Waiting for publisher"
state. Ask the publisher to create/keep the session active and re-check the code
has not expired (codes have a limited TTL).

## No audio despite "Connected", or `Transport: Relay` unexpectedly

ICE servers (STUN and short-lived TURN credentials) come from the backend's
`GET /api/webrtc/ice-servers` (see `IceServersRepository`); the SonicRelay
coturn deployment backs the production TURN entry, so relay should generally
work once the backend is reachable and authenticated. If the request fails
in a debug build, the app falls back to a public STUN-only server
(`stun:stun1.google.com:19302`, no TURN) — on strict/symmetric NATs that
fallback can leave the media path unable to traverse, or unable to relay at
all. In production the app never falls back to that STUN-only default
silently: an unreachable backend simply yields an empty ICE server list.
Check backend connectivity/auth and coturn reachability
(`sonicrelay-turn.hugodotnet.dev`, ports `3478/udp`, `3478/tcp`, `5349/tcp`)
first. To force relay-only ICE for debugging, use the "Force relay (TURN
only)" toggle in Settings.

## Local development checklist

1. Start the backend (see the backend repo) and note its HTTP/WS URLs.
2. Run the app with matching defines:
   ```sh
   flutter run \
     --dart-define=SONIC_RELAY_API_URL=http://10.0.2.2:5000 \
     --dart-define=SONIC_RELAY_WS_URL=ws://10.0.2.2:5000
   ```
   (Android emulator reaches the host via `10.0.2.2`.)
3. Log in, confirm device registration in Settings.
4. Create a session from the Windows publisher and enter the code.
