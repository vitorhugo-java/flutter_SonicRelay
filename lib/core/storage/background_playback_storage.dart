import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the viewer's "Keep audio playing in background" preference so it
/// survives app restarts. Defaults to enabled: the foreground service only ever
/// runs while a stream is actually active, so keeping it on by default just means
/// a stream the user started keeps playing when they background the app.
class BackgroundPlaybackStorage {
  const BackgroundPlaybackStorage(this._storage);

  static const _key = 'playback.keepInBackground';

  final FlutterSecureStorage _storage;

  Future<bool> read() async {
    final value = await _storage.read(key: _key);
    // Absent (never set) => on by default; only an explicit 'false' disables it.
    return value != 'false';
  }

  Future<void> write(bool value) =>
      _storage.write(key: _key, value: value ? 'true' : 'false');
}
