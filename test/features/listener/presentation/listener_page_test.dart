import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/features/listener/domain/listener_connection_state.dart';
import 'package:sonic_relay/features/listener/domain/listener_stats.dart';
import 'package:sonic_relay/features/listener/presentation/listener_page.dart';
import 'package:sonic_relay/features/listener/presentation/listener_view_model.dart';

class _StubListenerViewModel extends ListenerViewModel {
  _StubListenerViewModel(this._initial);

  final ListenerState _initial;

  @override
  ListenerState build() => _initial;

  @override
  Future<void> leave() async {}
}

Future<void> _pumpWith(WidgetTester tester, ListenerState state) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        listenerViewModelProvider.overrideWith(
          () => _StubListenerViewModel(state),
        ),
      ],
      child: const MaterialApp(home: ListenerPage()),
    ),
  );
}

void main() {
  testWidgets('renders the idle state', (tester) async {
    await _pumpWith(tester, const ListenerState());

    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Silent'), findsOneWidget);
    expect(find.text('Leave session'), findsOneWidget);
  });

  testWidgets('renders the connected state with live audio', (tester) async {
    await _pumpWith(
      tester,
      const ListenerState(
        connection: ListenerConnectionState.connected,
        stats: ListenerStats(iceState: 'Connected', hasRemoteAudio: true),
      ),
    );

    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('renders the failed state', (tester) async {
    await _pumpWith(
      tester,
      const ListenerState(
        connection: ListenerConnectionState.failed,
        stats: ListenerStats(iceState: 'Failed'),
      ),
    );

    expect(find.text('Connection failed'), findsOneWidget);
  });
}
