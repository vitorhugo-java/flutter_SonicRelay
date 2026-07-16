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
