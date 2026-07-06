# Android/Flutter Auth Completion Design

## Goal

Finish the Flutter authentication flow so the app supports **user registration**
(sign-up) alongside the existing sign-in, and reaches the same authenticated
steady state (persisted tokens, restored session, 401 refresh, `flutter_viewer`
device registration, correct navigation) through either entry point.

## Current State (do not rebuild)

The following already exist and are in scope only for verification and test
coverage — not reimplementation:

- **Login:** `AuthApi.login` → `POST /auth/login?useCookies=false`, `AuthRepository.login`.
- **Token persistence:** `SecureTokenStorage` over `flutter_secure_storage`; clear-on-logout.
- **Session restore:** `AuthRepository.restore` (validates via `/auth/me`, falls back to refresh, clears on failure).
- **401 refresh:** `AuthInterceptor` adds `Authorization: <tokenType> <accessToken>`, refreshes once per request on 401, clears tokens and fires `onSessionExpired` on failed refresh.
- **Device registration:** `DevicesRepository.ensureCurrentDevice` registers a `flutter_viewer` for `android`/`ios`, persists the backend UUID via `DeviceIdStorage`, and re-registers on missing/revoked IDs. `DevicesViewModel` triggers it when auth becomes authenticated.
- **Routing:** `authRedirect` sends restoring → `/loading`, unauthenticated → `/login`, authenticated-on-`/login`/`/loading` → `/join`.
- **Config:** `AppConfig.fromEnvironment` reads `SONIC_RELAY_API_URL` / `SONIC_RELAY_WS_URL` via `String.fromEnvironment` with local-only defaults.

## Gap (what this change delivers)

1. Register user DTO + API + repository method.
2. A `RegisterPage` reachable from `/register`.
3. LoginPage "Create an account" enabled and navigating to `/register`.
4. Router: `/register` reachable while unauthenticated; authenticated users leaving it land on `/join`.
5. Documentation of Android run commands (local + VPS) and coverage tests.

## Decisions

- **Post-register behavior: automatic login.** After a successful `POST /auth/register`,
  the repository immediately calls `login(email, password)` with the same
  credentials, reusing the established persistence + `/auth/me` path. This keeps a
  single authenticated code path and lets the existing router + `DevicesViewModel`
  drive navigation and device registration with no new wiring. If the backend ever
  returns a non-auto-loginable state (e.g. email confirmation required), the
  repository surfaces an `AuthFailure` and the page falls back to directing the
  user to sign in — no silent failure.
- **Reuse the auth pipeline, don't fork it.** `register` lives on the existing
  `AuthApi` / `DioAuthApi` / `AuthRepository`, and `AuthViewModel` gains a
  `register(...)` that mirrors `login(...)` state transitions
  (`authenticating` → `authenticated` / `unauthenticated(errorMessage)`).
- **`RegisterRequest` DTO** carries `email` and `password` only, matching the
  ASP.NET Identity `/auth/register` contract and the existing `LoginRequest`
  shape. `skipAuth` is set on the register call (no bearer token yet).
- **RegisterPage mirrors LoginPage visuals** (same `SonicCard` / `SonicTextField`
  / `SonicButton`, brand mark, gradient). It adds a confirm-password field and
  reuses the same email/password validation. No global UI redesign.
- **Router stays declarative.** Add a `/register` `GoRoute` and extend
  `authRedirect` so `/register` is allowed while unauthenticated and treated like
  `/login` once authenticated. `/loading` behavior is unchanged.

## API Contract

- `POST /auth/register` — body `{ "email": ..., "password": ... }`, `skipAuth: true`.
  Success is 2xx with no required body. On 400/409 (validation / duplicate email)
  the repository raises a friendly `AuthFailure`; other failures raise a generic
  connectivity `AuthFailure`, matching `login`'s error mapping.

## Navigation Flow

`/login` → tap "Create an account" → `/register` → submit → auto-login →
`AuthState.authenticated` → router redirect → `/join` → `DevicesViewModel`
registers the device. Registration failure keeps the user on `/register` with an
inline error.

## Config & Secrets

No new env keys. Tokens remain exclusively in `flutter_secure_storage`; nothing is
written to `SharedPreferences`. No backend URL is hardcoded outside `AppConfig`'s
local defaults. README documents Android runs against local and VPS backends via
`--dart-define`.

## Testing

- `AuthRepository`: login success, register success (auto-login persists tokens +
  loads user), register invalid/duplicate (`AuthFailure`), invalid login credentials.
- `TokenStorage`: write/read/clear round-trip (existing, confirm still green).
- `AuthInterceptor`: adds bearer token; refreshes once on 401 (existing, confirm).
- Router: unauthenticated users redirected to `/login`; `/register` allowed while
  unauthenticated; authenticated user on `/register` redirected to `/join`.
- Tests stay deterministic with fake `AuthApi` / `TokenStorage` (no real Dio,
  no network).

## Scope / Non-Goals

No WebRTC or signaling work (unless a compile error forces a minimal fix). No new
state-management library or service locator. No global UI redesign. No password
reset, email confirmation UI, or social login. Riverpod, GoRouter, Dio, and
`flutter_secure_storage` are retained.

## Acceptance

`flutter analyze` and `flutter test` pass; login still works; `/register` exists
and is reachable; the "Create an account" button is enabled; bearer token is sent;
401 refresh works; logout clears tokens; Android device registration occurs after
auth; no hardcoded backend URLs beyond `AppConfig` defaults.
