import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/core/storage/relay_mode_storage.dart';

class _FakeRelayModeStorage extends RelayModeStorage {
  _FakeRelayModeStorage() : super(const FlutterSecureStorage());

  bool? written;
  bool stored = false;

  @override
  Future<bool> read() async => stored;

  @override
  Future<void> write(bool value) async {
    written = value;
    stored = value;
  }
}

void main() {
  test('ForceRelayNotifier defaults to false and persists changes', () async {
    final storage = _FakeRelayModeStorage();
    final container = ProviderContainer(
      overrides: [relayModeStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    expect(container.read(forceRelayProvider), isFalse);

    await container.read(forceRelayProvider.notifier).set(true);

    expect(container.read(forceRelayProvider), isTrue);
    expect(storage.written, isTrue);
  });
}
