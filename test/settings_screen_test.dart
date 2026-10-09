import 'dart:io';

import 'package:BPOS/pos/settings_screen.dart';
import 'package:BPOS/store.dart';
import 'package:BPOS/theme.dart';
import 'package:BPOS/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final docs = Directory.systemTemp.createTempSync('bpos_settings');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => docs.path);
    m.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'), (_) async => ['none']);
    m.setMockStreamHandler(const EventChannel('dev.fluttercommunity.plus/connectivity_status'), MockStreamHandler.inline(onListen: (_, __) {}));
  });

  Future<Store> pump(WidgetTester t, Size size) async {
    // The test font is wider than real fonts; ignore layout overflow noise.
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) onError?.call(d);
    };
    addTearDown(() => FlutterError.onError = onError);
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    late Store store;
    await t.runAsync(() async {
      store = Store();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await t.pumpWidget(StoreScope(store: store, child: MaterialApp(theme: buildTheme(), home: const SettingsScreen())));
    await t.pump();
    return store;
  }

  testWidgets('wide: sidebar and detail side by side, Web ordering opens', (t) async {
    await pump(t, const Size(1200, 800));
    expect(find.text('Backoffice connection'), findsOneWidget, reason: 'first section shown');
    expect(find.text('Printers'), findsWidgets);
    await t.tap(find.text('Web ordering').first);
    await t.pump();
    expect(find.text('Accept web orders'), findsOneWidget);
    expect(find.text('Enter the address above to get the link and QR code.'), findsOneWidget);
  });

  testWidgets('narrow: list first, then a section, back returns to the list', (t) async {
    await pump(t, const Size(420, 800));
    expect(find.text('Backoffice connection'), findsNothing);
    await t.tap(find.text('Connection').first);
    await t.pump();
    expect(find.text('Backoffice connection'), findsOneWidget);
    await t.tap(find.byIcon(Icons.arrow_back));
    await t.pump();
    expect(find.text('Backoffice connection'), findsNothing);
  });
}
