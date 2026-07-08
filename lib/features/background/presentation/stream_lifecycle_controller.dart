import 'dart:async';

import '../../../core/diagnostics/sonic_log.dart';
import '../../listener/domain/listener_connection_state.dart';
import '../data/foreground_stream_service.dart';

/// Creates the bounded reconnect timeout. Injectable so tests can fire it by
/// hand instead of waiting on a real clock.
typedef LifecycleTimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

/// Decides when the foreground service should run, based on the viewer's
/// connection state, whether the app is foreground/background, and the
/// "keep playing in background" setting. Pure and fully unit-tested: it holds no
/// WebRTC state and only drives [ForegroundStreamService] plus two callbacks.
class StreamLifecycleController {
  StreamLifecycleController({
    required ForegroundStreamService service,
    required bool Function() keepPlayingInBackground,
    required Future<void> Function() onStopRequested,
    required Future<void> Function() onReconnectRequested,
    Duration reconnectWindow = const Duration(seconds: 45),
    LifecycleTimerFactory? timerFactory,
  }) : _service = service,
       _keepPlaying = keepPlayingInBackground,
       _onStopRequested = onStopRequested,
       _onReconnectRequested = onReconnectRequested,
       _reconnectWindow = reconnectWindow,
       _timerFactory = timerFactory ?? Timer.new {
    _actionSubscription = _service.actions.listen(_handleAction);
  }

  final ForegroundStreamService _service;
  final bool Function() _keepPlaying;
  final Future<void> Function() _onStopRequested;
  final Future<void> Function() _onReconnectRequested;
  final Duration _reconnectWindow;
  final LifecycleTimerFactory _timerFactory;

  StreamSubscription<ForegroundServiceAction>? _actionSubscription;
  Timer? _reconnectTimer;

  ListenerConnectionState _state = ListenerConnectionState.idle;
  bool _inForeground = true;
  bool _running = false;

  /// A stream that should keep the process alive while backgrounded.
  static bool _isActive(ListenerConnectionState state) => switch (state) {
    ListenerConnectionState.waitingForOffer ||
    ListenerConnectionState.negotiating ||
    ListenerConnectionState.connecting ||
    ListenerConnectionState.connected ||
    ListenerConnectionState.reconnecting => true,
    ListenerConnectionState.idle ||
    ListenerConnectionState.failed ||
    ListenerConnectionState.ended ||
    ListenerConnectionState.disconnected => false,
  };

  void onConnectionState(ListenerConnectionState state) {
    _state = state;
    _reconcile();
  }

  void onAppForegroundChanged(bool inForeground) {
    _inForeground = inForeground;
    _reconcile();
  }

  void _reconcile() {
    final active = _isActive(_state);

    if (_running) {
      if (!active) {
        // The stream ended, failed, or was left while the service was running.
        _running = false;
        _cancelReconnectTimer();
        unawaited(_service.stop(endedNotice: _endedNotice(_state)));
        return;
      }
      if (_inForeground) {
        // The user is back in the app; the UI is visible so the persistent
        // notification is no longer warranted.
        _running = false;
        _cancelReconnectTimer();
        unawaited(_service.stop());
        return;
      }
      // Still backgrounded and active: refresh the notification for the new
      // state and (dis)arm the bounded reconnect timer.
      unawaited(_service.update(_notificationFor(_state)));
      _syncReconnectTimer();
      return;
    }

    if (active && !_inForeground && _keepPlaying()) {
      _running = true;
      sonicLog('Background', 'starting foreground service (state=$_state)');
      unawaited(_service.start(_notificationFor(_state)));
      _syncReconnectTimer();
    }
  }

  void _syncReconnectTimer() {
    if (_running && _state == ListenerConnectionState.reconnecting) {
      _reconnectTimer ??= _timerFactory(_reconnectWindow, _onReconnectTimeout);
    } else {
      _cancelReconnectTimer();
    }
  }

  void _onReconnectTimeout() {
    _reconnectTimer = null;
    if (!_running || _state != ListenerConnectionState.reconnecting) return;
    // Bounded background reconnect exhausted: stop burning battery, tell the
    // user, and give up the peer connection.
    _running = false;
    sonicLog('Background', 'reconnect window elapsed -> stopping service');
    unawaited(
      _service.stop(endedNotice: 'Stream ended — could not reconnect.'),
    );
    unawaited(_onStopRequested());
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _handleAction(ForegroundServiceAction action) {
    switch (action) {
      case ForegroundServiceAction.stop:
        unawaited(_onStopRequested());
      case ForegroundServiceAction.reconnect:
        unawaited(_onReconnectRequested());
      case ForegroundServiceAction.open:
        // The main window is brought forward natively; nothing to do here.
        break;
    }
  }

  /// Stops the service and drops background state — used on logout so no
  /// notification or process-survival outlives the session.
  Future<void> forceStop() async {
    _cancelReconnectTimer();
    if (!_running) return;
    _running = false;
    await _service.stop();
  }

  Future<void> dispose() async {
    _cancelReconnectTimer();
    await _actionSubscription?.cancel();
  }

  ForegroundStreamNotification _notificationFor(ListenerConnectionState state) {
    final (body, showReconnect) = switch (state) {
      ListenerConnectionState.waitingForOffer => (
        'Waiting for the publisher to start streaming…',
        false,
      ),
      ListenerConnectionState.negotiating ||
      ListenerConnectionState.connecting => ('Connecting to the stream…', false),
      ListenerConnectionState.connected => ('Listening to the stream', false),
      ListenerConnectionState.reconnecting => (
        'Connection dropped — reconnecting…',
        true,
      ),
      _ => ('SonicRelay is running', false),
    };
    return ForegroundStreamNotification(
      title: 'SonicRelay',
      body: body,
      showReconnect: showReconnect,
    );
  }

  String? _endedNotice(ListenerConnectionState state) => switch (state) {
    ListenerConnectionState.ended => 'The publisher ended the stream.',
    ListenerConnectionState.failed => 'The stream connection failed.',
    // A clean viewer-initiated leave needs no lingering notification.
    _ => null,
  };
}
