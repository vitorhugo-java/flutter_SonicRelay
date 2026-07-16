import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/sonic_relay_app.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/core/storage/secure_token_storage.dart';
import 'package:sonic_relay/features/auth/domain/auth_session.dart';
import 'package:sonic_relay/features/listener/presentation/listener_page.dart';
import 'package:sonic_relay/features/sessions/presentation/join_session_page.dart';
import 'package:sonic_relay/features/settings/presentation/settings_page.dart';

class EmptyTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}
  @override
  Future<AuthSession?> read() async => null;
  @override
  Future<void> write(AuthSession session) async {}
}

String _testDiagnosticsDirectory() =>
    Directory.systemTemp.createTempSync('sonicrelay_app_test_').path;

ProviderScope testApp() => ProviderScope(
  overrides: [
    tokenStorageProvider.overrideWithValue(EmptyTokenStorage()),
    diagnosticsDirectoryProvider.overrideWithValue(_testDiagnosticsDirectory()),
  ],
  child: const SonicRelayApp(),
);

void main() {
  testWidgets('uses a dark Material 3 theme', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme?.useMaterial3, isTrue);
    expect(materialApp.theme?.brightness, Brightness.dark);
  });

  testWidgets('login presents branding and fields', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.text('Hear every detail.'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('feature pages show presentation-only status content', (
    tester,
  ) async {
    Future<void> pumpPage(Widget page) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            diagnosticsDirectoryProvider.overrideWithValue(_testDiagnosticsDirectory()),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: page,
          ),
        ),
      );
    }

    await pumpPage(const JoinSessionPage());
    expect(find.text('Join stream'), findsOneWidget);

    await pumpPage(const ListenerPage());
    expect(find.text('Audio monitor'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('WebRTC / ICE'), findsOneWidget);

    await pumpPage(const SettingsPage());
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets('login fits a common small Android viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
