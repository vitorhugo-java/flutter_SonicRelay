# Android/Flutter Auth Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add user registration (sign-up) to the existing Flutter auth flow so
either sign-in or sign-up reaches the same authenticated steady state, and verify
the already-implemented auth/device/router behavior with tests.

**Architecture:** Registration extends the existing auth pipeline
(`AuthApi` → `AuthRepository` → `AuthViewModel`) and reuses login for persistence
and navigation. A new `RegisterPage` is reached via a new `/register` route; the
router redirect gains a `/register` allowance. Device registration, token
refresh, and secure storage are unchanged.

**Tech Stack:** Flutter, Dart, Riverpod, GoRouter, Dio, flutter_secure_storage, flutter_test

---

### Task 1: Register transport + repository (TDD)

**Files:**
- Create: `lib/features/auth/data/dto/register_request.dart`
- Modify: `lib/features/auth/data/auth_api.dart`
- Modify: `lib/features/auth/data/auth_repository.dart`
- Modify: `test/features/auth/data/auth_repository_test.dart`

- [ ] Add `RegisterRequest { email, password }` with `toJson`, mirroring `LoginRequest`.
- [ ] Add `Future<void> register(RegisterRequest)` to `AuthApi`; implement in `DioAuthApi` as `POST /auth/register` with `Options(extra: {'skipAuth': true})`.
- [ ] Add `Future<AuthSession> register({email, password})` to `AuthRepository`: call `_api.register(...)`, then delegate to `login(email, password)`; map 400/409 to a friendly `AuthFailure`, other `DioException`s to the generic connectivity `AuthFailure`.
- [ ] Extend the fake `AuthApi` in the test with a no-op/error-configurable `register`.
- [ ] Write tests (confirm RED first): register success persists tokens and loads the user; register on 400/409 throws `AuthFailure`; keep existing login-success and invalid-credentials coverage.
- [ ] Run `flutter test test/features/auth/data/auth_repository_test.dart`; confirm GREEN.

### Task 2: AuthViewModel register action

**Files:**
- Modify: `lib/features/auth/presentation/login_view_model.dart`

- [ ] Add `Future<void> register({email, password})` mirroring `login`: set `AuthState.authenticating()`, call `_repository.register(...)`, set `authenticated`/`unauthenticated(errorMessage)` on `AuthFailure`, generic message otherwise.

### Task 3: RegisterPage

**Files:**
- Create: `lib/features/auth/presentation/register_page.dart`

- [ ] Build `RegisterPage` as a `ConsumerStatefulWidget` reusing the LoginPage layout (gradient, `_BrandMark`, `SonicCard`, `SonicTextField`, `SonicButton`).
- [ ] Fields: email, password, confirm-password. Reuse the login email regex; require non-empty password and matching confirmation; show inline field errors and `auth.errorMessage`.
- [ ] On submit call `authViewModelProvider.notifier.register(...)`; show loading while `AuthStatus.authenticating`.
- [ ] Add a "Back to sign in" `TextButton` that calls `context.go('/login')`.

### Task 4: LoginPage + router wiring

**Files:**
- Modify: `lib/features/auth/presentation/login_page.dart`
- Modify: `lib/app/router/app_router.dart`
- Modify: `test/app/app_router_test.dart`

- [ ] Enable the "Create an account" button (remove `onPressed: null` / "coming soon"); `onPressed: () => context.go('/register')`; import `go_router`.
- [ ] Register the `/register` `GoRoute` → `const RegisterPage()`.
- [ ] Update `authRedirect`: while unauthenticated, allow both `/login` and `/register`; when authenticated, redirect `/login`, `/loading`, and `/register` to `/join`. Keep `/loading` during restore.
- [ ] Add/confirm tests: unauthenticated → `/login`; `/register` allowed while unauthenticated; authenticated on `/register` → `/join`.
- [ ] Run `flutter test test/app/app_router_test.dart`; confirm GREEN.

### Task 5: Verify existing guarantees (confirm, don't rebuild)

**Files:**
- Reference only: `test/core/storage/secure_token_storage_test.dart`, `test/core/http/auth_interceptor_test.dart`

- [ ] Confirm `TokenStorage` write/read/clear coverage exists and passes; add a missing case only if absent.
- [ ] Confirm `AuthInterceptor` tests cover bearer-token injection and single 401 refresh; add a missing case only if absent.

### Task 6: Docs + acceptance verification

**Files:**
- Modify: `README.md`

- [ ] Document running Android against the local backend and the VPS backend via `--dart-define=SONIC_RELAY_API_URL=... --dart-define=SONIC_RELAY_WS_URL=...`, and note that registration auto-logs-in and reaches `/join`.
- [ ] `dart format` changed Dart files.
- [ ] Run `flutter analyze`; require exit code 0.
- [ ] Run `flutter test`; require exit code 0.
- [ ] Review `git diff --check` and re-check every acceptance criterion from the spec.
- [ ] Commit and push to `claude/loving-albattani-fh9xel`.
