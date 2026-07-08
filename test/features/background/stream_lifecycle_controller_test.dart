import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/features/background/data/foreground_stream_service.dart';
import 'package:sonic_relay/features/background/presentation/stream_lifecycle_controller.dart';
import 'package:sonic_relay/features/listener/domain/listener_connection_state.dart';

class _FakeService implements ForegroundStreamService {
  final _actions = StreamController<ForegroundServiceAction>.broadcast();
  final List<ForegroundStreamNotification> started = [];
  final List<ForegroundStreamNotification> updated = [];
  final List<String?> stopped = [];
  bool disposed = false;

  void emit(ForegroundServiceAction action) => _actions.add(action);

  @override
  Stream<ForegroundServiceAction> get actions => _actions.stream;

  @override
  Future<void> start(ForegroundStreamNotification notification) async =>
      started.add(notification);

  @override
  Future<void> update(ForegroundStreamNotification notification) async =>
      updated.add(notification);

  @override
  Future<void> stop({String? endedNotice}) async => stopped.add(endedNotice);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _actions.close();
  }
}

/// Captures the timer callback so tests can fire the reconnect timeout by hand.
class _ManualTimer implements Timer {
  _ManualTimer(this.callback);
  final void Function() callback;
  bool _active = true;

  void fire() => callback();

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

void main() {
  late _FakeService service;
  late bool keepPlaying;
  late int stopRequests;
  late int reconnectRequests;
  _ManualTimer? lastTimer;

  StreamLifecycleController build() => StreamLifecycleController(
    service: service,
    keepPlayingInBackground: () => keepPlaying,
    onStopRequested: () async => stopRequests++,
    onReconnectRequested: () async => reconnectRequests++,
    reconnectWindow: const Duration(seconds: 45),
    timerFactory: (duration, cb) => lastTimer = _ManualTimer(cb),
  );

  setUp(() {
    service = _FakeService();
    keepPlaying = true;
    stopRequests = 0;
    reconnectRequests = 0;
    lastTimer = null;
  });

  test('backgrounding while a stream is active starts the service', () {
    final controller = build();
    controller.onConnectionState(ListenerConnectionState.connected);

    controller.onAppForegroundChanged(false);

    expect(service.started, hasLength(1));
    expect(service.started.single.body, contains('Listening'));
  });

  test('does not start when the setting is disabled', () {
    keepPlaying = false;
    final controller = build();
    controller.onConnectionState(ListenerConnectionState.connected);

    controller.onAppForegroundChanged(false);

    expect(service.started, isEmpty);
  });

  test('does not start when no stream is active', () {
    final controller = build();
    controller.onConnectionState(ListenerConnectionState.idle);

    controller.onAppForegroundChanged(false);

    expect(service.started, isEmpty);
  });

  test('returning to the foreground stops the service without a notice', () {
    final controller = build();
    controller.onConnectionState(ListenerConnectionState.connected);
    controller.onAppForegroundChanged(false);

    controller.onAppForegroundChanged(true);

    expect(service.stopped, [null]);
  });

  test('does not start twice while already running', () {
    final controller = build();
    controller.onConnectionState(ListenerConnectionState.connected);
    controller.onAppForegroundChanged(false);
    controller.onConnectionState(ListenerConnectionState.connected);

    expect(service.started, hasLength(1));
  });

  test('a state change while backgrounded updates the notification', () {
    final controller = build();
    controller.onConnectionState(ListenerConnectionState.connected);
    controller.onAppForegroundChanged(false);

    controller.onConnectionState(ListenerConnectionState.reconnecting);

    expect(service.updated.last.showReconnect, isTrue);
  });

  test('a terminal state while running stops with an ended notice', () {
    final controller = build();
    controller.onConnectionState(ListenerConnectionState.connected);
    controller.onAppForegroundChanged(false);

    controller.onConnectionState(ListenerConnectionState.ended);

    expect(service.stopped, hasLength(1));
    expect(service.stopped.single, isNotNull);
  });

  test('reconnect timeout stops the service and gives up the peer connection',
      () {
    final controller = build();
    controller.onConnectionState(ListenerConnectionState.connected);
    controller.onAppForegroundChanged(false);
    controller.onConnectionState(ListenerConnectionState.reconnecting);

    expect(lastTimer, isNotNull);
    lastTimer!.fire();

    expect(service.stopped.single, isNotNull);
    expect(stopRequests, 1);
  });

  test('recovering before the reconnect window cancels the timeout', () {
    final controller = build();
    controller.onConnectionState(ListenerConnectionState.connected);
    controller.onAppForegroundChanged(false);
    controller.onConnectionState(ListenerConnectionState.reconnecting);
    controller.onConnectionState(ListenerConnectionState.connected);

    expect(lastTimer!.isActive, isFalse);
  });

  test('the notification stop action requests leaving the session', () async {
    build();
    service.emit(ForegroundServiceAction.stop);
    await Future<void>.delayed(Duration.zero);

    expect(stopRequests, 1);
  });

  test('the notification reconnect action requests a reconnect', () async {
    build();
    service.emit(ForegroundServiceAction.reconnect);
    await Future<void>.delayed(Duration.zero);

    expect(reconnectRequests, 1);
  });

  test('forceStop stops a running service (logout)', () {
    final controller = build();
    controller.onConnectionState(ListenerConnectionState.connected);
    controller.onAppForegroundChanged(false);

    controller.forceStop();

    expect(service.stopped, [null]);
  });
}
