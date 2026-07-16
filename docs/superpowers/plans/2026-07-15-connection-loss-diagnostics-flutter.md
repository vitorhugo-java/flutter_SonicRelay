# Connection-Loss Diagnostics (Flutter) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the debug-only `sonicLog()` with a persisted, redacted, exportable/clearable diagnostic log, and capture the concrete reason the signaling WebSocket disconnects — the data needed to diagnose "loses connection when minimized/backgrounded/closed."

**Architecture:** A new `lib/core/diagnostics/` module (`DiagnosticEvent`, `DiagnosticRedactor`, `DiagnosticLog`) mirrors the design already shipped in `windows_SonicRelay`'s `DiagnosticLog`: a 100-event in-memory ring buffer plus a redacted JSONL file per day, with retention cleanup, `clear()`, and `export()`. It's wired into the app via a Riverpod `Provider`, seeded at startup with `path_provider`'s app-support directory. `WebSocketClient` gains a bounded disconnect-reason stream (the single highest-value site, per a Codex review on the paired Windows PR that specifically flagged low-level transport failures as the data this feature must capture) and `SignalingClient`/the app's lifecycle handler are migrated to route through `DiagnosticLog`. A Settings-page section adds Export (via `share_plus`) and Clear (via the existing `showDialog` confirmation pattern already used for account deletion).

**Tech Stack:** Flutter/Dart (SDK ^3.10.0), `flutter_riverpod`, `path_provider`, `share_plus`.

## Global Constraints

- Retention default: 3 days (delete `viewer-*.jsonl` files older than that when `DiagnosticLog` is constructed).
- Every write to `RecentEvents`/disk must be serialized through the same async queue so `clear()` can never race a write that already passed the in-memory update — this is the exact bug a Codex review caught in the paired Windows PR (`WriteAsync` updating memory before acquiring its lock); do not repeat it here.
- All new "reason" data is a fixed enum, never raw error text, matching `DiagnosticRedactor`'s job of never leaking tokens/SDP/ICE/emails into the log.
- Diagnostics must never throw into or crash the app — every disk operation is wrapped and swallows I/O errors.
- Scope note: this pass fully migrates `websocket_client.dart` (Task 4) and `sonic_relay_app.dart` + `signaling_client.dart` (Task 5) off `sonicLog`, since together they cover app-lifecycle, transport-level close reason, and signaling-level connect/reconnect/leave — the three categories the spec calls out. `sonicLog` call sites in `rtc_peer_connection_factory.dart`, `ice_servers_repository.dart`, `stream_lifecycle_controller.dart`, `foreground_stream_service.dart`, `webrtc_receiver_service.dart`, and `session_waiting_page.dart` are **not** migrated in this pass (still `debugPrint`-only); they are lower-signal for a connection-loss diagnosis and migrating all nine files' DI wiring in one pass was judged out of scope here. Call this out explicitly if asked to extend coverage later — do not claim full migration.

---

### Task 1: `DiagnosticEvent` and `DiagnosticRedactor`

**Files:**
- Create: `lib/core/diagnostics/diagnostic_event.dart`
- Create: `lib/core/diagnostics/diagnostic_redactor.dart`
- Test: `test/core/diagnostics/diagnostic_redactor_test.dart`

**Interfaces:**
- Produces: `DiagnosticEvent(timestamp, category, message, properties)` with `toJson()`; `DiagnosticRedactor.redact(String value): String`, `DiagnosticRedactor.isSensitiveKey(String key): bool`. Consumed by `DiagnosticLog` in Task 2.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/diagnostics/diagnostic_redactor_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/diagnostics/diagnostic_redactor.dart';

void main() {
  group('DiagnosticRedactor', () {
    test('redacts bearer tokens', () {
      expect(
        DiagnosticRedactor.redact('Authorization: Bearer abc.def-123'),
        'Authorization: Bearer [REDACTED]',
      );
    });

    test('redacts JWT-like strings', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PYE0d';
      expect(DiagnosticRedactor.redact('token=$jwt'), isNot(contains(jwt)));
      expect(DiagnosticRedactor.redact('token=$jwt'), contains('[REDACTED]'));
    });

    test('redacts email addresses', () {
      expect(
        DiagnosticRedactor.redact('user user@example.com signed in'),
        'user [REDACTED] signed in',
      );
    });

    test('redacts SDP payloads', () {
      final result = DiagnosticRedactor.redact(
        'sdp=v=0 o=- 12345 2 IN IP4 127.0.0.1 candidate:1 1 UDP 1 10.0.0.1 5000 typ host',
      );
      expect(result, isNot(contains('127.0.0.1')));
      expect(result, contains('[REDACTED]'));
    });

    test('redacts ICE candidate lines', () {
      final result = DiagnosticRedactor.redact(
        'candidate:1 1 UDP 2130706431 10.0.0.5 54321 typ host',
      );
      expect(result, isNot(contains('10.0.0.5')));
      expect(result, contains('[REDACTED]'));
    });

    test('leaves ordinary text untouched', () {
      expect(
        DiagnosticRedactor.redact('connecting to wss://example.test/ws'),
        'connecting to wss://example.test/ws',
      );
    });

    test('identifies sensitive property keys', () {
      expect(DiagnosticRedactor.isSensitiveKey('accessToken'), isTrue);
      expect(DiagnosticRedactor.isSensitiveKey('sdp'), isTrue);
      expect(DiagnosticRedactor.isSensitiveKey('iceCandidate'), isTrue);
      expect(DiagnosticRedactor.isSensitiveKey('sessionId'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/diagnostics/diagnostic_redactor_test.dart`
Expected: FAIL — `package:sonic_relay/core/diagnostics/diagnostic_redactor.dart` doesn't exist.

- [ ] **Step 3: Implement `DiagnosticEvent` and `DiagnosticRedactor`**

```dart
// lib/core/diagnostics/diagnostic_event.dart
import 'dart:convert';

/// One structured, already-redacted diagnostic log line.
class DiagnosticEvent {
  DiagnosticEvent({
    required this.timestamp,
    required this.category,
    required this.message,
    this.properties = const {},
  });

  final DateTime timestamp;
  final String category;
  final String message;
  final Map<String, String> properties;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'category': category,
    'message': message,
    'properties': properties,
  };

  String encode() => jsonEncode(toJson());
}
```

```dart
// lib/core/diagnostics/diagnostic_redactor.dart
/// Strips secrets, SDP/ICE payloads and emails out of log lines before they
/// reach memory or disk. Mirrors windows_SonicRelay's DiagnosticRedactor rules.
///
/// Note: Dart's RegExp (ECMAScript-flavored) has no inline `(?i)` case flag
/// like .NET's regex engine — verified empirically (it throws
/// FormatException). Every case-insensitive pattern below uses the
/// `caseSensitive: false` constructor parameter instead.
class DiagnosticRedactor {
  const DiagnosticRedactor._();

  static const _redacted = '[REDACTED]';

  static final _bearerToken = RegExp(
    r'\bbearer\s+[^\s,;]+',
    caseSensitive: false,
  );
  static final _jwt = RegExp(r'\bey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b');
  static final _email = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );
  static final _sdpPayload = RegExp(
    r'\bsdp\s*=\s*.*',
    caseSensitive: false,
  );
  static final _iceCandidate = RegExp(
    r'candidate:[^\r\n]+',
    caseSensitive: false,
  );
  static final _sensitiveAssignment = RegExp(
    r'\b(password|access[_-]?token|refresh[_-]?token|token|code)\s*=\s*[^\s&]+',
    caseSensitive: false,
  );
  static final _sensitiveKey = RegExp(
    r'^(password|access[_-]?token|refresh[_-]?token|token|authorization|sdp|ice[_-]?candidate)$',
    caseSensitive: false,
  );

  static String redact(String? value) {
    if (value == null || value.isEmpty) return value ?? '';
    var result = value.replaceAllMapped(
      _sensitiveAssignment,
      (match) => '${match[1]}=$_redacted',
    );
    result = result.replaceAll(_bearerToken, 'Bearer $_redacted');
    result = result.replaceAll(_jwt, _redacted);
    result = result.replaceAll(_email, _redacted);
    result = result.replaceAll(_sdpPayload, 'sdp=$_redacted');
    result = result.replaceAll(_iceCandidate, _redacted);
    return result;
  }

  static bool isSensitiveKey(String key) => _sensitiveKey.hasMatch(key);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/diagnostics/diagnostic_redactor_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/diagnostics/diagnostic_event.dart lib/core/diagnostics/diagnostic_redactor.dart test/core/diagnostics/diagnostic_redactor_test.dart
git commit -m "Add DiagnosticEvent and DiagnosticRedactor"
```

---

### Task 2: `DiagnosticLog` — retention, write queue, clear, export

**Files:**
- Create: `lib/core/diagnostics/diagnostic_log.dart`
- Test: `test/core/diagnostics/diagnostic_log_test.dart`

**Interfaces:**
- Produces: `DiagnosticLog(String directory, {Duration retention})`, `.write(String category, String message, [Map<String,String>? properties]): Future<void>`, `.recentEvents: List<DiagnosticEvent>`, `.clear(): Future<void>`, `.export(): Future<String>` (returns the exported file path). Consumed by app wiring (Task 3) and by `WebSocketClient`/`SignalingClient`/`sonic_relay_app.dart` (Tasks 4–5).

- [ ] **Step 1: Write the failing tests**

```dart
// test/core/diagnostics/diagnostic_log_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/diagnostics/diagnostic_log.dart';

void main() {
  group('DiagnosticLog', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sonicrelay_diag_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('write appends a redacted JSON line and keeps it in recentEvents', () async {
      final log = DiagnosticLog(tempDir.path);

      await log.write('auth', 'login failed password=hunter2', {'token': 'secret'});

      expect(log.recentEvents, hasLength(1));
      final content = await File(log.logPath).readAsString();
      expect(content, isNot(contains('hunter2')));
      expect(content, isNot(contains('secret')));
      expect(content, contains('[REDACTED]'));
    });

    test('construction deletes files older than retention and keeps newer ones', () async {
      final oldFile = File('${tempDir.path}/viewer-20200101.jsonl');
      final newFile = File('${tempDir.path}/viewer-${_today()}.jsonl');
      await oldFile.writeAsString('{}\n');
      await newFile.writeAsString('{}\n');
      await oldFile.setLastModified(DateTime.now().subtract(const Duration(days: 10)));

      DiagnosticLog(tempDir.path, retention: const Duration(days: 3));

      expect(oldFile.existsSync(), isFalse);
      expect(newFile.existsSync(), isTrue);
    });

    test('clear deletes log files and empties recentEvents', () async {
      final log = DiagnosticLog(tempDir.path);
      await log.write('auth', 'signed in');
      expect(log.recentEvents, isNotEmpty);
      expect(File(log.logPath).existsSync(), isTrue);

      await log.clear();

      expect(log.recentEvents, isEmpty);
      expect(File(log.logPath).existsSync(), isFalse);
    });

    test('a write already queued past the in-memory update cannot escape a clear', () async {
      // Regression guard mirroring the Codex-caught race on the paired Windows PR:
      // recentEvents and the disk append must serialize as one unit with clear(),
      // otherwise a queued write can land on disk right after a clear "succeeded".
      final log = DiagnosticLog(tempDir.path);
      await log.write('auth', 'first');

      final blocker = log.write('auth', 'second');
      await log.clear();
      await blocker;

      final recentHasSecond = log.recentEvents.any((e) => e.message == 'second');
      final file = File(log.logPath);
      final fileHasSecond = file.existsSync() && (await file.readAsString()).contains('second');
      expect(recentHasSecond, fileHasSecond);
    });

    test('export concatenates retained files into one file and returns its path', () async {
      final log = DiagnosticLog(tempDir.path);
      await log.write('auth', 'first');
      await log.write('auth', 'second');

      final exportedPath = await log.export();

      final content = await File(exportedPath).readAsString();
      expect(content, contains('first'));
      expect(content, contains('second'));
    });

    test('recentEvents is capped at 100 entries', () async {
      final log = DiagnosticLog(tempDir.path);
      for (var i = 0; i < 105; i++) {
        await log.write('auth', 'event-$i');
      }

      expect(log.recentEvents, hasLength(100));
      expect(log.recentEvents.first.message, 'event-5');
      expect(log.recentEvents.last.message, 'event-104');
    });
  });
}

String _today() {
  final now = DateTime.now().toUtc();
  String pad2(int n) => n.toString().padLeft(2, '0');
  return '${now.year}${pad2(now.month)}${pad2(now.day)}';
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/diagnostics/diagnostic_log_test.dart`
Expected: FAIL — `diagnostic_log.dart` doesn't exist.

- [ ] **Step 3: Implement `DiagnosticLog`**

```dart
// lib/core/diagnostics/diagnostic_log.dart
import 'dart:async';
import 'dart:io';

import 'diagnostic_event.dart';
import 'diagnostic_redactor.dart';

/// Persisted, redacted, bounded diagnostic log for the viewer. Mirrors
/// windows_SonicRelay's DiagnosticLog: a JSONL file per day, a 100-event
/// in-memory ring buffer, retention cleanup, clear, and single-file export.
class DiagnosticLog {
  DiagnosticLog(this._directory, {Duration retention = const Duration(days: 3)}) {
    _deleteExpiredFiles(retention);
  }

  static const _eventLimit = 100;

  final String _directory;
  final List<DiagnosticEvent> _recentEvents = [];

  // Serializes every write/clear/export as one queue, so recentEvents and the
  // disk file always move together — the same class of race a Codex review
  // caught in the paired Windows PR (RecentEvents updated before the write
  // lock was held) cannot happen here because both mutations run inside the
  // same queued closure.
  Future<void> _queue = Future<void>.value();

  String get logPath => '$_directory/viewer-${_todayStamp()}.jsonl';

  List<DiagnosticEvent> get recentEvents => List.unmodifiable(_recentEvents);

  Future<void> write(
    String category,
    String message, [
    Map<String, String>? properties,
  ]) {
    final safeProperties = <String, String>{
      for (final entry in (properties ?? const {}).entries)
        DiagnosticRedactor.redact(entry.key): DiagnosticRedactor.isSensitiveKey(entry.key)
            ? '[REDACTED]'
            : DiagnosticRedactor.redact(entry.value),
    };
    final event = DiagnosticEvent(
      timestamp: DateTime.now().toUtc(),
      category: DiagnosticRedactor.redact(category),
      message: DiagnosticRedactor.redact(message),
      properties: safeProperties,
    );

    return _enqueue(() async {
      _recentEvents.add(event);
      if (_recentEvents.length > _eventLimit) {
        _recentEvents.removeRange(0, _recentEvents.length - _eventLimit);
      }
      final dir = Directory(_directory);
      if (!await dir.exists()) await dir.create(recursive: true);
      await File(logPath).writeAsString(
        '${event.encode()}\n',
        mode: FileMode.append,
      );
    });
  }

  /// Deletes every retained log file and empties the in-memory buffer.
  Future<void> clear() => _enqueue(() async {
    for (final file in _logFiles()) {
      await _tryDelete(file);
    }
    _recentEvents.clear();
  });

  /// Concatenates every retained log file (oldest first) into one exported
  /// file under `<directory>/exports/` and returns its path. Lines are
  /// already redacted at write time — this is a plain concatenation.
  Future<String> export() => _enqueue(() async {
    final exportDir = Directory('$_directory/exports');
    await exportDir.create(recursive: true);
    final exportPath = '${exportDir.path}/sonicrelay-logs-${_timestampStamp()}.jsonl';
    final output = File(exportPath).openWrite();
    try {
      final files = _logFiles()..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        await output.addStream(file.openRead());
      }
    } finally {
      await output.close();
    }
    return exportPath;
  });

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    // Keep the queue alive even if this step failed, otherwise every later
    // write/clear/export would be skipped once one link in the chain rejects.
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  void _deleteExpiredFiles(Duration retention) {
    try {
      final cutoff = DateTime.now().subtract(retention);
      for (final file in _logFiles()) {
        if (file.statSync().modified.isBefore(cutoff)) {
          file.deleteSync();
        }
      }
    } catch (_) {
      // Retention cleanup must never stop the app from starting.
    }
  }

  List<File> _logFiles() {
    final dir = Directory(_directory);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((file) => file.uri.pathSegments.last.startsWith('viewer-') &&
            file.path.endsWith('.jsonl'))
        .toList();
  }

  Future<void> _tryDelete(File file) async {
    try {
      await file.delete();
    } catch (_) {
      // Best-effort, matching the constructor's retention cleanup.
    }
  }

  String _todayStamp() {
    final now = DateTime.now().toUtc();
    return '${now.year}${_pad2(now.month)}${_pad2(now.day)}';
  }

  String _timestampStamp() {
    final now = DateTime.now().toUtc();
    return '${now.year}${_pad2(now.month)}${_pad2(now.day)}-'
        '${_pad2(now.hour)}${_pad2(now.minute)}${_pad2(now.second)}';
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/core/diagnostics/diagnostic_log_test.dart`
Expected: PASS — all six cases.

- [ ] **Step 5: Commit**

```bash
git add lib/core/diagnostics/diagnostic_log.dart test/core/diagnostics/diagnostic_log_test.dart
git commit -m "Add DiagnosticLog: retention, write queue, clear, export"
```

---

### Task 3: Wire `DiagnosticLog` into the app (dependencies + DI + bootstrap)

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/app/di/app_providers.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Produces: `diagnosticLogProvider: Provider<DiagnosticLog>` (in `app_providers.dart`), consumed by Tasks 4–5 and the Settings page (Task 6).

- [ ] **Step 1: Add the two new dependencies**

Run:
```bash
flutter pub add path_provider share_plus
```
Expected: `pubspec.yaml`'s `dependencies:` gains `path_provider: ^<resolved>` and `share_plus: ^<resolved>` (both were already transitive or absent; this makes `path_provider` a direct, declared dependency instead of relying on another package's transitive pull-in, and adds `share_plus` fresh).

- [ ] **Step 2: Add the provider**

In `lib/app/di/app_providers.dart`, add near the other storage-adjacent providers:

```dart
import '../../core/diagnostics/diagnostic_log.dart';

/// The directory DiagnosticLog writes under — resolved once at startup (see
/// main.dart) since path_provider's directory lookup is async and this
/// provider must be synchronous to construct DiagnosticLog eagerly.
final diagnosticsDirectoryProvider = Provider<String>(
  (ref) => throw UnimplementedError('overridden in main()'),
);

final diagnosticLogProvider = Provider<DiagnosticLog>(
  (ref) => DiagnosticLog(ref.watch(diagnosticsDirectoryProvider)),
);
```

- [ ] **Step 3: Resolve the directory at startup and override the provider**

In `lib/main.dart`:

```dart
import 'package:path_provider/path_provider.dart';

import 'app/di/app_providers.dart';
// ...(existing imports)...

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const secureStorage = FlutterSecureStorage();
  final savedServerUrl =
      await const ServerConfigStorage(secureStorage).read() ??
      AppConfig.defaultServerUrl;
  final savedForceRelay = await const RelayModeStorage(secureStorage).read();
  final savedKeepPlaying =
      await const BackgroundPlaybackStorage(secureStorage).read();
  final diagnosticsDirectory = (await getApplicationSupportDirectory()).path;

  runApp(
    ProviderScope(
      overrides: [
        serverUrlProvider.overrideWith(() => ServerUrlNotifier(savedServerUrl)),
        forceRelayProvider.overrideWith(() => ForceRelayNotifier(savedForceRelay)),
        backgroundPlaybackEnabledProvider.overrideWith(
          () => BackgroundPlaybackNotifier(savedKeepPlaying),
        ),
        diagnosticsDirectoryProvider.overrideWithValue(diagnosticsDirectory),
      ],
      child: const SonicRelayApp(),
    ),
  );
}
```

- [ ] **Step 4: Build to verify wiring compiles**

Run: `flutter analyze lib/main.dart lib/app/di/app_providers.dart`
Expected: no errors (there is no automated test for this step — it is pure DI wiring with no branching logic; `diagnosticsDirectoryProvider`'s override is exercised implicitly by every widget test that pumps `SonicRelayApp`, none of which exist yet for this feature until Task 6).

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/app/di/app_providers.dart lib/main.dart
git commit -m "Wire DiagnosticLog into the app via path_provider-backed DI"
```

---

### Task 4: `WebSocketClient` disconnect-reason stream

**Files:**
- Modify: `lib/core/websocket/websocket_client.dart`
- Test: `test/core/websocket/websocket_client_test.dart`

**Interfaces:**
- Produces: `enum WebSocketDisconnectReason { normal, serverClosed, transportError, connectFailed }`, `WebSocketClient.disconnectReasons: Stream<WebSocketDisconnectReason>`. Consumed by `SignalingClient` (optionally, in Task 5) and directly by anything that wants transport-level diagnostics; this task also migrates every `sonicLog` call in this file to `DiagnosticLog`, since this is the exact file a Codex review on the paired Windows PR flagged as the one that must not stay debug-only.

- [ ] **Step 1: Write the failing tests**

Append to `test/core/websocket/websocket_client_test.dart` (inside `group('WebSocketClient', ...)`, e.g. after the `'disconnect stops reconnect attempts'` test):

```dart
    test('disconnectReasons emits serverClosed when the peer closes the socket', () async {
      final connections = <FakeWebSocketConnection>[];
      final client = WebSocketClient(
        connector: (uri, headers) async {
          final connection = FakeWebSocketConnection();
          connections.add(connection);
          return connection;
        },
        scheduleTimer: _instantTimer,
      );
      addTearDown(client.dispose);
      final reasons = <WebSocketDisconnectReason>[];
      final sub = client.disconnectReasons.listen(reasons.add);

      await client.connect(Uri.parse('wss://example.test/ws'));
      connections.single.emitDone();
      await Future<void>.delayed(Duration.zero);

      expect(reasons, [WebSocketDisconnectReason.serverClosed]);
      await sub.cancel();
    });

    test('disconnectReasons emits transportError on a stream error', () async {
      final connections = <FakeWebSocketConnection>[];
      final client = WebSocketClient(
        connector: (uri, headers) async {
          final connection = FakeWebSocketConnection();
          connections.add(connection);
          return connection;
        },
        scheduleTimer: _instantTimer,
      );
      addTearDown(client.dispose);
      final reasons = <WebSocketDisconnectReason>[];
      final sub = client.disconnectReasons.listen(reasons.add);

      await client.connect(Uri.parse('wss://example.test/ws'));
      connections.single.emitError(Exception('boom'));
      await Future<void>.delayed(Duration.zero);

      expect(reasons, [WebSocketDisconnectReason.transportError]);
      await sub.cancel();
    });

    test('disconnectReasons emits connectFailed when the connector throws', () async {
      var attempts = 0;
      final client = WebSocketClient(
        connector: (uri, headers) async {
          attempts++;
          if (attempts == 1) throw Exception('connect failed');
          return FakeWebSocketConnection();
        },
        scheduleTimer: _instantTimer,
      );
      addTearDown(client.dispose);
      final reasons = <WebSocketDisconnectReason>[];
      final sub = client.disconnectReasons.listen(reasons.add);

      await client.connect(Uri.parse('wss://example.test/ws'));
      await Future<void>.delayed(Duration.zero);

      expect(reasons, [WebSocketDisconnectReason.connectFailed]);
      await sub.cancel();
    });

    test('disconnectReasons emits normal on an explicit disconnect', () async {
      final client = WebSocketClient(
        connector: (uri, headers) async => FakeWebSocketConnection(),
        scheduleTimer: _instantTimer,
      );
      addTearDown(client.dispose);
      final reasons = <WebSocketDisconnectReason>[];
      final sub = client.disconnectReasons.listen(reasons.add);

      await client.connect(Uri.parse('wss://example.test/ws'));
      await client.disconnect();

      expect(reasons, [WebSocketDisconnectReason.normal]);
      await sub.cancel();
    });
```

Add `emitError` to the `FakeWebSocketConnection` test helper at the top of the same file (next to `emit`/`emitDone`):

```dart
  void emitError(Object error) => _controller.addError(error);
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/websocket/websocket_client_test.dart`
Expected: FAIL to compile — `WebSocketDisconnectReason` and `disconnectReasons` don't exist, and `emitError` doesn't exist on the fake.

- [ ] **Step 3: Add the enum, the stream, and migrate this file's `sonicLog` calls**

In `lib/core/websocket/websocket_client.dart`, replace the `sonic_log.dart` import with the diagnostics log:

```dart
import '../diagnostics/diagnostic_log.dart';
```

Add the enum near `WebSocketConnectionState`:

```dart
enum WebSocketDisconnectReason { normal, serverClosed, transportError, connectFailed }
```

Add a required `DiagnosticLog` constructor parameter and the new stream controller:

```dart
class WebSocketClient {
  WebSocketClient({
    required WebSocketConnector connector,
    required DiagnosticLog diagnosticLog,
    ReconnectPolicy reconnectPolicy = const ReconnectPolicy(),
    Timer Function(Duration delay, void Function() callback)? scheduleTimer,
    math.Random? random,
  }) : _connector = connector,
       _diagnosticLog = diagnosticLog,
       _reconnectPolicy = reconnectPolicy,
       _scheduleTimer = scheduleTimer ?? Timer.new,
       _random = random ?? math.Random();

  final WebSocketConnector _connector;
  final DiagnosticLog _diagnosticLog;
  ...
  final _disconnectReasonController =
      StreamController<WebSocketDisconnectReason>.broadcast();

  Stream<WebSocketDisconnectReason> get disconnectReasons =>
      _disconnectReasonController.stream;
```

Replace the five `sonicLog(...)` call sites and add the disconnect-reason firing:

```dart
  Future<void> _attemptConnect() async {
    if (_stopped) return;
    if (_attempt == 0) {
      _stateController.add(WebSocketConnectionState.connecting);
    }
    try {
      unawaited(_diagnosticLog.write('WebSocket', 'connecting to $_uri (attempt $_attempt)'));
      final headers = await _headersProvider();
      final connection = await _connector(_uri!, headers);
      if (_stopped) {
        await connection.close();
        return;
      }
      _connection = connection;
      _attempt = 0;
      unawaited(_diagnosticLog.write('WebSocket', 'connected to $_uri'));
      _stateController.add(WebSocketConnectionState.connected);
      _subscription = connection.stream.listen(
        (dynamic data) {
          if (data is String) {
            _messageController.add(WebSocketMessage.decode(data));
          }
        },
        onDone: () {
          unawaited(_diagnosticLog.write('WebSocket', 'socket closed by peer'));
          _disconnectReasonController.add(WebSocketDisconnectReason.serverClosed);
          _handleDisconnect();
        },
        onError: (Object error) {
          unawaited(_diagnosticLog.write('WebSocket', 'socket error'));
          _disconnectReasonController.add(WebSocketDisconnectReason.transportError);
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (error) {
      unawaited(_diagnosticLog.write('WebSocket', 'connect failed'));
      _disconnectReasonController.add(WebSocketDisconnectReason.connectFailed);
      _scheduleReconnect();
    }
  }
```

Note: the error's message is deliberately **not** interpolated into the log text (unlike the
original `'socket error: $error'`/`'connect failed: $error'`) — a raw exception message could
contain a URI with credentials or other incidental data `DiagnosticRedactor` wasn't written to
anticipate. The bounded `WebSocketDisconnectReason` on the new stream carries the "why" instead.

Fire `normal` on an explicit disconnect, in `disconnect()`:

```dart
  Future<void> disconnect() async {
    _stopped = true;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _connection?.close();
    _connection = null;
    _disconnectReasonController.add(WebSocketDisconnectReason.normal);
    _stateController.add(WebSocketConnectionState.disconnected);
  }
```

And close the new controller in `dispose()`:

```dart
  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
    await _messageController.close();
    await _disconnectReasonController.close();
  }
```

- [ ] **Step 4: Update the call site in `app_providers.dart`**

In `lib/app/di/app_providers.dart`, update `webSocketClientProvider` to pass the log:

```dart
final webSocketClientProvider = Provider<WebSocketClient>(
  (ref) => WebSocketClient(
    connector: ioWebSocketConnector,
    diagnosticLog: ref.watch(diagnosticLogProvider),
  ),
);
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/core/websocket/websocket_client_test.dart`
Expected: PASS — the four new cases plus every pre-existing case (each existing test's `WebSocketClient(...)` construction needs a `diagnosticLog:` argument added; use a shared test helper to avoid repeating it — add near the top of the test file:

```dart
DiagnosticLog _testLog() =>
    DiagnosticLog(Directory.systemTemp.createTempSync('sonicrelay_ws_test_').path);
```

and pass `diagnosticLog: _testLog()` into every existing `WebSocketClient(...)` construction in this file).

- [ ] **Step 6: Commit**

```bash
git add lib/core/websocket/websocket_client.dart lib/app/di/app_providers.dart test/core/websocket/websocket_client_test.dart
git commit -m "Add WebSocketClient.disconnectReasons and migrate its logging to DiagnosticLog"
```

---

### Task 5: Migrate app-lifecycle and `SignalingClient` logging

**Files:**
- Modify: `lib/app/sonic_relay_app.dart`
- Modify: `lib/features/signaling/data/signaling_client.dart`
- Modify: `lib/app/di/app_providers.dart`

**Interfaces:**
- Consumes: `diagnosticLogProvider` (Task 3). No new public interface produced.

- [ ] **Step 1: Migrate `sonic_relay_app.dart`'s lifecycle log**

In `lib/app/sonic_relay_app.dart`, replace the `sonic_log.dart` import with:

```dart
import '../core/diagnostics/diagnostic_log.dart';
```

Replace the single call site:

```dart
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive/hidden/paused/detached must only ever update UI/service
    // visibility (via the lifecycle controller below), never be treated as an
    // explicit leave — only a user-initiated Stop/Leave, logout, or terminal
    // connection state closes the active stream.
    unawaited(
      ref.read(diagnosticLogProvider).write('Lifecycle', 'app lifecycle -> $state'),
    );
    final inForeground = state == AppLifecycleState.resumed;
    ref
        .read(streamLifecycleControllerProvider)
        .onAppForegroundChanged(inForeground);
  }
```

Add `import 'dart:async';` for `unawaited` if not already present, and add
`import 'di/app_providers.dart';` if not already imported (it already is, per the existing
`streamLifecycleControllerProvider` reference).

- [ ] **Step 2: Migrate `signaling_client.dart`'s five call sites**

In `lib/features/signaling/data/signaling_client.dart`, replace the `sonic_log.dart` import:

```dart
import '../../../core/diagnostics/diagnostic_log.dart';
```

Add a required constructor parameter:

```dart
class SignalingClient {
  SignalingClient({
    required WebSocketClient webSocketClient,
    required TokenStorage tokenStorage,
    required DiagnosticLog diagnosticLog,
    SignalingMessageMapper mapper = const SignalingMessageMapper(),
    Random? random,
  }) : _webSocketClient = webSocketClient,
       _tokenStorage = tokenStorage,
       _diagnosticLog = diagnosticLog,
       _mapper = mapper,
       _random = random ?? Random() {
    _connectionSubscription = _webSocketClient.connectionState.listen(
      _handleTransportState,
    );
    _messageSubscription = _webSocketClient.messages.listen(_handleRawMessage);
  }

  final WebSocketClient _webSocketClient;
  final TokenStorage _tokenStorage;
  final DiagnosticLog _diagnosticLog;
```

Replace each of the five call sites:

```dart
    final uri = _buildUri(session.signalingUrl, session.sessionId, deviceId);
    unawaited(_diagnosticLog.write(
      'Signaling',
      'connect sessionId=${session.sessionId} deviceId=$deviceId uri=$uri',
    ));
```

```dart
  Future<Map<String, String>> _resolveHeaders() async {
    final authSession = await _tokenStorage.read();
    unawaited(_diagnosticLog.write(
      'Signaling',
      'resolved auth header hasToken=${authSession != null}',
    ));
```

```dart
  void _handleRawMessage(WebSocketMessage raw) {
    final message = _mapper.fromWebSocketMessage(raw);
    unawaited(_diagnosticLog.write(
      'Signaling',
      'recv type=${message.type.wireValue} from=${message.from} to=${message.to}',
    ));
```

```dart
  void _send(SignalingMessageType type, Map<String, Object?> payload, {String? to}) {
    final session = _session;
    if (session == null) return;
    unawaited(_diagnosticLog.write('Signaling', 'send type=${type.wireValue} to=$to'));
```

```dart
  Future<void> leave() async {
    unawaited(_diagnosticLog.write('Signaling', 'leave sessionId=${_session?.sessionId}'));
    _leaving = true;
    await _webSocketClient.disconnect();
  }
```

Add `import 'dart:async';` if not already present (it is, via the existing `unawaited(leave())` call in `_handleRawMessage`).

- [ ] **Step 3: Update the call site in `app_providers.dart`**

```dart
final signalingClientProvider = Provider<SignalingClient>(
  (ref) => SignalingClient(
    webSocketClient: ref.watch(webSocketClientProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
    diagnosticLog: ref.watch(diagnosticLogProvider),
  ),
);
```

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`
Expected: PASS — this task adds no new tests of its own (pure logging migration, no branching logic changed); every existing test must still pass. Any test that constructs `SignalingClient` directly (check `test/features/signaling/`) needs a `diagnosticLog:` argument added, the same way Task 4 added one to `WebSocketClient` test construction sites.

- [ ] **Step 5: Commit**

```bash
git add lib/app/sonic_relay_app.dart lib/features/signaling/data/signaling_client.dart lib/app/di/app_providers.dart
git commit -m "Migrate app-lifecycle and SignalingClient logging to DiagnosticLog"
```

---

### Task 6: Settings page — Export and Clear

**Files:**
- Modify: `lib/features/settings/presentation/settings_page.dart`

**Interfaces:**
- Consumes: `diagnosticLogProvider` (Task 3), `DiagnosticLog.export()`/`.clear()` (Task 2).

Export shares the file via `share_plus`'s `SharePlus.instance.share(...)`. Clear reuses the
existing `showDialog<bool>` + `AlertDialog` confirmation pattern already used by
`_DeleteAccountButton` in this same file — no new confirmation UX needs inventing.

- [ ] **Step 1: Add the Diagnostics section and its widget**

In `lib/features/settings/presentation/settings_page.dart`, add the imports:

```dart
import 'package:share_plus/share_plus.dart';

import '../../../app/di/app_providers.dart';
```

Insert a new section into the `Column` in `SettingsPage.build`, right after the existing
`SonicCard` (the one containing Server/Connection/Playback/Appearance rows) and before the
`'Your devices'` row:

```dart
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Diagnostics',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _DiagnosticsSection(),
```

Add the new widget at the bottom of the file, alongside `_DeleteAccountButton`:

```dart
class _DiagnosticsSection extends ConsumerStatefulWidget {
  const _DiagnosticsSection();

  @override
  ConsumerState<_DiagnosticsSection> createState() => _DiagnosticsSectionState();
}

class _DiagnosticsSectionState extends ConsumerState<_DiagnosticsSection> {
  bool _isBusy = false;
  String? _message;

  Future<void> _export() async {
    setState(() {
      _isBusy = true;
      _message = null;
    });
    try {
      final path = await ref.read(diagnosticLogProvider).export();
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
      setState(() => _message = 'Exported diagnostics log.');
    } catch (_) {
      setState(() => _message = 'Export failed: could not write the log file.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _confirmAndClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear diagnostics log?'),
        content: const Text(
          'This permanently deletes the on-device diagnostics log. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isBusy = true;
      _message = null;
    });
    try {
      await ref.read(diagnosticLogProvider).clear();
      setState(() => _message = 'Cleared the diagnostics log.');
    } catch (_) {
      setState(() => _message = 'Clear failed: could not delete the log file(s).');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SonicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SettingsRow(
            icon: Icons.bug_report_outlined,
            title: 'Diagnostics log',
            subtitle: 'Redacted connection/session history for support requests',
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: SonicButton(
                  label: 'Export logs',
                  icon: Icons.ios_share_rounded,
                  onPressed: _isBusy ? null : _export,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SonicButton(
                  label: 'Clear logs',
                  icon: Icons.delete_outline_rounded,
                  isSecondary: true,
                  onPressed: _isBusy ? null : _confirmAndClear,
                ),
              ),
            ],
          ),
          if (_message case final message?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
```

`SonicButton`'s exact constructor parameters (`label`, `icon`, `isSecondary`, `onPressed`)
already match the usage on the pre-existing `'Log out'` button a few lines above in this same
file — reuse that signature as shown.

- [ ] **Step 2: Manual verification**

Run: `flutter run` (or `flutter test` cannot exercise `share_plus`'s platform channel, so this
step is manual), navigate to Settings, tap **Export logs** (confirm the OS share sheet opens
with a `.jsonl` attachment), tap **Clear logs**, confirm the dialog, and confirm the "Cleared…"
message appears and a subsequent Export produces an (almost) empty file.

- [ ] **Step 3: Run the full test suite to confirm nothing else broke**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/features/settings/presentation/settings_page.dart pubspec.yaml pubspec.lock
git commit -m "Add Export/Clear diagnostics actions to the Settings page"
```
