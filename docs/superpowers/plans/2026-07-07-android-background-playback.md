# Android Background Playback — Implementation Plan

Spec: `docs/superpowers/specs/2026-07-07-android-background-playback-design.md`
Issue: #13

## Step 1 — Foreground service abstraction (data)

- `lib/features/background/data/foreground_stream_service.dart`
  - `enum ForegroundServiceAction { open, stop, reconnect }`.
  - `class ForegroundStreamNotification { title, body, showReconnect }`.
  - `abstract interface class ForegroundStreamService` — `start`, `update`,
    `stop({endedNotice})`, `actions`, `dispose`.
  - `NoopForegroundStreamService` (non-Android / tests).
  - `AndroidForegroundStreamServiceBridge` over `MethodChannel`
    `sonicrelay/foreground` + `EventChannel` `sonicrelay/foreground/events`.

## Step 2 — Lifecycle controller (presentation, TDD)

- Test first: `test/features/background/stream_lifecycle_controller_test.dart`
  with a `FakeForegroundStreamService` + injected timer factory.
- `lib/features/background/presentation/stream_lifecycle_controller.dart`
  - Track connection state + app-foreground flag; start/update/stop per spec.
  - Bounded reconnect timer (default 45s) → stop + ended notice + `onStopRequested`.
  - Route `actions`: stop → `onStopRequested`, reconnect → `onReconnectRequested`.
  - `forceStop()` for logout.

## Step 3 — Setting storage (TDD)

- Test first: `test/core/storage/background_playback_storage_test.dart`.
- `lib/core/storage/background_playback_storage.dart` (mirror `RelayModeStorage`,
  default true).

## Step 4 — DI + wiring

- `app_providers.dart`: `foregroundStreamServiceProvider`,
  `backgroundPlaybackStorageProvider`, `backgroundPlaybackEnabledProvider`
  (`BackgroundPlaybackNotifier`), `streamLifecycleControllerProvider`.
- `ListenerViewModel`: forward connection states into the controller.
- `SonicRelayApp`: `WidgetsBindingObserver` → `onAppForegroundChanged`.
- `AuthViewModel.logout()` / `expireSession()` → controller `forceStop()`.
- `main.dart`: seed `backgroundPlaybackEnabledProvider` from storage.

## Step 5 — Settings UI

- `lib/features/settings/presentation/widgets/keep_playing_toggle.dart`
  + add to `settings_page.dart`.
- Widget test.

## Step 6 — Native Android + manifest

- `AndroidManifest.xml`: add `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`; declare
  `SonicRelayForegroundService` with `foregroundServiceType="mediaPlayback"`.
- `SonicRelayForegroundService.kt` + method/event channel registration in
  `MainActivity.kt`.

## Step 7 — Verify + docs

- `flutter analyze`, `flutter test`.
- README: document background playback + manual QA steps.
