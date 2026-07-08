import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/app_providers.dart';
import '../data/auth_repository.dart';
import '../domain/auth_session.dart';

enum AuthStatus { restoring, unauthenticated, authenticating, authenticated }

class AuthState {
  const AuthState._(this.status, {this.session, this.errorMessage});
  const AuthState.restoring() : this._(AuthStatus.restoring);
  const AuthState.unauthenticated({String? errorMessage})
    : this._(AuthStatus.unauthenticated, errorMessage: errorMessage);
  const AuthState.authenticating() : this._(AuthStatus.authenticating);
  const AuthState.authenticated({AuthSession? session})
    : this._(AuthStatus.authenticated, session: session);

  final AuthStatus status;
  final AuthSession? session;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

final authViewModelProvider = NotifierProvider<AuthViewModel, AuthState>(
  AuthViewModel.new,
);

class AuthViewModel extends Notifier<AuthState> {
  late final AuthRepository _repository;

  @override
  AuthState build() {
    _repository = ref.watch(authRepositoryProvider);
    ref.watch(authInterceptorProvider).onSessionExpired = expireSession;
    Future<void>.microtask(_restore);
    return const AuthState.restoring();
  }

  Future<void> _restore() async {
    try {
      final session = await _repository.restore();
      state = session == null
          ? const AuthState.unauthenticated()
          : AuthState.authenticated(session: session);
    } catch (_) {
      state = const AuthState.unauthenticated();
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = const AuthState.authenticating();
    try {
      final session = await _repository.login(email: email, password: password);
      state = AuthState.authenticated(session: session);
    } on AuthFailure catch (error) {
      state = AuthState.unauthenticated(errorMessage: error.message);
    } catch (_) {
      state = const AuthState.unauthenticated(
        errorMessage: 'Unable to sign in. Please try again.',
      );
    }
  }

  Future<void> logout() async {
    await ref.read(streamLifecycleControllerProvider).forceStop();
    await _repository.logout();
    state = const AuthState.unauthenticated();
  }

  void expireSession() {
    unawaited(ref.read(streamLifecycleControllerProvider).forceStop());
    state = const AuthState.unauthenticated(
      errorMessage: 'Your session has expired. Please sign in again.',
    );
  }
}
