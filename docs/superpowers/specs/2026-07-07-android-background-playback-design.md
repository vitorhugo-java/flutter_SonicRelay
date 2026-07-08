# Android Background Playback Design

## Goal

Keep the Android viewer receiving and playing SonicRelay audio while the app is
backgrounded, the screen is locked, or the user switches apps. Session/token
persistence is out of scope (issue #11). This issue (#13) covers the Android
runtime/background behaviour during an *active* stream, using an Android
Foreground Service of type `mediaPlayback` with a persistent notification.

## Constraints (from issue #13)

- Backgrounding must keep the WebRTC receiver, signaling socket, audio playback,
  and reconnect logic alive. Locking the screen must not stop audio.
- Use a real Foreground Service (`mediaPlayback`) with a persistent notification —
  no fake polling, infinite timers, or isolate hacks.
- Manifest declares the service + `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, and `POST_NOTIFICATIONS`.
- Notification actions where practical: open, stop/leave, reconnect.
- Background reconnection is bounded; on exhaustion, stop the service and show a
  "stream ended" notification.
- A `Keep audio playing in background` setting, on by default, only meaningful
  while a stream is active.
- Android 14+ must not throw `MissingForegroundServiceTypeException` /
  `SecurityException`. Do not start the service from `BOOT_COMPLETED`.
- No auth tokens in notifications, intents, logs, or plain files.
- Keep WebRTC internals behind the existing service layer so the UI can disappear
  without destroying the connection.
- `flutter analyze` and `flutter test` pass.

## Architecture

The heavy WebRTC/signaling lifetime already lives in `WebRtcReceiverService` and
`SignalingClient`, owned by Riverpod providers on the root `ProviderContainer` —
not by any widget. That is exactly what "the UI can disappear without destroying
the connection" requires, so no ownership move is needed; the connection already
survives the widget tree being paused. This issue adds the **process-survival**
layer (the foreground service) plus the **decision layer** that starts/stops it.

New feature slice: `lib/features/background`.

```
ListenerConnectionState ─┐
app foreground/background┼─▶ StreamLifecycleController ─▶ ForegroundStreamService
Keep-in-background setting┘         │  (start/update/stop, bounded reconnect timer)
                                    ▼
                          ForegroundServiceAction stream (open/stop/reconnect)
                                    │
              ┌─────────────────────┼──────────────────────┐
        onStopRequested        (open handled          onReconnectRequested
        → leave()               natively)              → reconnect()
```

### `ForegroundStreamService` (data)

`lib/features/background/data/foreground_stream_service.dart`

- `abstract interface class ForegroundStreamService`
  - `Future<void> start(ForegroundStreamNotification notification)`
  - `Future<void> update(ForegroundStreamNotification notification)`
  - `Future<void> stop({String? endedNotice})`
  - `Stream<ForegroundServiceAction> get actions`
  - `Future<void> dispose()`
- `ForegroundStreamNotification({ required String title, required String body,
  bool showReconnect = false })` — plain, token-free strings only.
- `enum ForegroundServiceAction { open, stop, reconnect }`
- `AndroidForegroundStreamServiceBridge` — real impl over a `MethodChannel`
  (`sonicrelay/foreground`: `start` / `update` / `stop`) and an `EventChannel`
  (`sonicrelay/foreground/events`) that surfaces notification-button taps as
  `ForegroundServiceAction`s. Constructed only on Android.
- `NoopForegroundStreamService` — every method is a no-op with an empty action
  stream, used on non-Android platforms and in tests that don't assert on it.

### Native Android

`android/app/src/main/kotlin/.../background/SonicRelayForegroundService.kt` — a
`Service` started with `startForeground(id, notification, FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)`.
Builds a persistent, non-dismissable notification on a low-importance channel with
"Open", "Stop", and (optionally) "Reconnect" actions whose `PendingIntent`s route
back through the service and are forwarded to Dart over the EventChannel.
`MainActivity.kt` registers the method/event channels and translates `start`,
`update`, `stop` into service intents. The manifest declares the service with
`android:foregroundServiceType="mediaPlayback"` and the three permissions above.
No token or session data is ever placed in intents/extras.

### `StreamLifecycleController` (presentation)

`lib/features/background/presentation/stream_lifecycle_controller.dart` — the pure,
fully unit-tested decision core. Inputs it is fed:

- `onConnectionState(ListenerConnectionState)` — from the listener view model.
- `onAppForegroundChanged(bool inForeground)` — from an app-lifecycle observer.
- callbacks: `keepPlayingInBackground()` (setting), `onStopRequested()` (leave),
  `onReconnectRequested()`.
- injectable `reconnectWindow` (default 45s) and a `timerFactory` so the bounded
  reconnect timeout is testable without a real clock.

Rules:

- **Active stream** = `waitingForOffer | negotiating | connecting | connected |
  reconnecting`. Terminal = `ended | failed | disconnected | idle`.
- App goes to **background** while active **and** setting enabled → `start` the
  service with a state-appropriate notification (idempotent; no double-start).
- App returns to **foreground** → `stop` the service (UI is visible again).
- While running, a connection-state change → `update` the notification text and
  the `showReconnect` flag (shown while `reconnecting`).
- A terminal state while running → `stop(endedNotice: …)` so a normal (non-ongoing)
  notification explains the stream ended.
- Entering `reconnecting` while running arms the bounded timer; if it fires still
  reconnecting → `stop(endedNotice: …)` **and** `onStopRequested()` (give up the
  peer connection). Leaving `reconnecting` cancels the timer.
- Notification actions: `stop` → `onStopRequested()`; `reconnect` →
  `onReconnectRequested()`; `open` → handled natively (bring app forward).

### Setting storage

`lib/core/storage/background_playback_storage.dart` mirrors `RelayModeStorage`
(`FlutterSecureStorage`, key `playback.keepInBackground`, default **true**).
`backgroundPlaybackEnabledProvider` (a `NotifierProvider<…, bool>` mirroring
`ForceRelayNotifier`) exposes/persists it; `main()` seeds the initial value. A
`KeepPlayingToggle` row is added to the settings card.

### Wiring

- `streamLifecycleControllerProvider` builds the controller with the Android
  bridge (or noop), reading the setting via `keepPlayingInBackground`, and
  wiring `onStopRequested`/`onReconnectRequested` to the listener view model.
- `ListenerViewModel` forwards receiver connection states into the controller.
- `SonicRelayApp` hosts a `WidgetsBindingObserver` that calls
  `onAppForegroundChanged` on resume/pause.
- `AuthViewModel.logout()` and `expireSession()` call the controller's
  `forceStop()` so logout stops the service and drops background state.

## Tests

- `StreamLifecycleController` (unit): background+active+enabled starts; disabled
  does not start; foreground stops a running service; terminal state stops with an
  ended notice; reconnect timeout stops + notifies + requests leave, and a recovery
  before timeout cancels it; `stop`/`reconnect` notification actions invoke the
  right callbacks; no double-start when already running.
- `BackgroundPlaybackStorage` (unit): round-trips true/false and defaults to true.
- `KeepPlayingToggle`/settings (widget): toggle reflects and updates the provider.

Native Kotlin + manifest are verified by the CI `build-android` job and documented
manual QA (below); they are not exercised by `flutter test`.

## Manual QA (documented in PR)

1. Join a stream, lock the phone → audio continues; persistent notification shown.
2. Switch to another app → audio continues.
3. Notification "Open" → app returns to the live session with correct state.
4. Notification "Stop" → stream leaves and the service stops.
5. Kill Wi-Fi briefly → "reconnecting" notification; restore → recovers. Leave off
   past the window → service stops with a "stream ended" notification.
6. Log out while streaming → service stops.
7. Android 14/15 target: no `MissingForegroundServiceTypeException` /
   `SecurityException`.

## Acceptance criteria

- `flutter analyze` and `flutter test` exit 0.
- Manifest declares the `mediaPlayback` service and required permissions.
- Backgrounding/locking keeps audio playing behind a persistent notification.
- Notification can reopen and can stop the session; stopping/logout stops the
  service.
- Bounded background reconnect; exhaustion stops the service with a notice.
- No token/session data in logs, notifications, intents, or plain storage.
