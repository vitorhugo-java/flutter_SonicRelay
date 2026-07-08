import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the viewer's "force relay (TURN only)" preference so it survives
/// app restarts. Stored as a simple string flag next to the other settings.
class RelayModeStorage {
  const RelayModeStorage(this._storage);

  static const _key = 'webrtc.forceRelay';

  final FlutterSecureStorage _storage;

  Future<bool> read() async => (await _storage.read(key: _key)) == 'true';

  Future<void> write(bool value) =>
      _storage.write(key: _key, value: value ? 'true' : 'false');
}
