import 'dart:io';

import 'package:bistro_pos/pos/kitchen_screen.dart';
import 'package:bistro_pos/pos/order_taking.dart';
import 'package:bistro_pos/pos/orders_screen.dart';
import 'package:bistro_pos/pos/payments_screen.dart';
import 'package:bistro_pos/pos/pos_shell.dart';
import 'package:bistro_pos/pos/tables_screen.dart';
import 'package:bistro_pos/store.dart';
import 'package:bistro_pos/theme.dart';
import 'package:bistro_pos/widgets/common.dart';
import 'package:bistro_pos/widgets/keys.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real POS shell with the real Store: device plugins are faked
/// (documents folder, connectivity), everything else is the app as shipped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('bpos_keys');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => docs.path);
    m.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'), (_) async => ['none']);
    m.setMockStreamHandler(const EventChannel('dev.fluttercommunity.plus/connectivity_status'), MockStreamHandler.inline(onListen: (_, __) {}));
  });

  testWidgets('F-keys switch tabs and / jumps to the menu search on the real POS', (t) async {
    final onError = FlutterError.onError;
    // The test font is wider than real fonts; ignore layout overflow noise.
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) onError?.call(d);
    };
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await t.binding.setSurfaceSize(const Size(1400, 900));
    late Store store;
    await t.runAsync(() async {
      store = Store();
      await Future<void>.delayed(const Duration(milliseconds: 500)); // let it load
    });
    await t.pumpWidget(StoreScope(store: store, child: MaterialApp(theme: buildTheme(), home: const PosShell())));
    await t.pump();
    await t.pump();

    expect(find.byType(OrderTakingScreen), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget, reason: 'desktop shows the shortcuts button');

    Future<void> press(LogicalKeyboardKey k) async {
      await t.sendKeyEvent(k);
      await t.pump();
      await t.pump();
    }

    await press(LogicalKeyboardKey.f2);
    expect(find.byType(TablesScreen), findsOneWidget, reason: 'F2 → Tables');
    await press(LogicalKeyboardKey.f3);
    expect(find.byType(OrdersScreen), findsOneWidget, reason: 'F3 → Orders');
    await press(LogicalKeyboardKey.f4);
    expect(find.byType(PaymentsScreen), findsOneWidget, reason: 'F4 → Payments');
    await press(LogicalKeyboardKey.f5);
    expect(find.byType(KitchenScreen), findsOneWidget, reason: 'F5 → Kitchen');
    await press(LogicalKeyboardKey.f1);
    expect(find.byType(OrderTakingScreen), findsOneWidget, reason: 'F1 → New order');

    await t.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await t.pump();
    expect(isTyping(), isTrue, reason: '/ focuses the menu search');

    await press(LogicalKeyboardKey.f12);
    expect(find.text('Keyboard shortcuts'), findsOneWidget, reason: 'F12 → help');

    await t.pumpWidget(const SizedBox());
    store.dispose();
    debugDefaultTargetPlatformOverride = null;
    FlutterError.onError = onError;
  });
}
