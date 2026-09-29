import 'dart:io';

import 'package:bistro_pos/captain/captain.dart';
import 'package:bistro_pos/captain/pair_screen.dart';
import 'package:bistro_pos/link/captain_link.dart';
import 'package:bistro_pos/link/pos_host.dart';
import 'package:bistro_pos/models.dart';
import 'package:bistro_pos/store.dart';
import 'package:bistro_pos/theme.dart';
import 'package:bistro_pos/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The captain's real screens, paired over a real socket with a real POS:
/// tap a table, seat 2, add an item, send the KOT, and see it land on the POS.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  testWidgets('captain seats a table and sends a KOT that arrives on the POS', (t) async {
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) onError?.call(d); // test font is wider than real ones
    };
    await t.binding.setSurfaceSize(const Size(420, 900));
    final docs = Directory.systemTemp.createTempSync('bpos_capflow');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => docs.path);
    m.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'), (_) async => ['none']);
    m.setMockStreamHandler(const EventChannel('dev.fluttercommunity.plus/connectivity_status'), MockStreamHandler.inline(onListen: (_, __) {}));

    late Store pos, cap;
    late PosHost host;
    late CaptainLink link;
    Future<void> settle([int ms = 300]) async {
      await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
    }

    await t.runAsync(() async {
      pos = Store();
      cap = Store(mirror: true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      pos.menu
        ..clear()
        ..add(const MenuItem(id: 'p-porotta', code: '003', cat: 'Bread', name: 'Porotta', price: 20));
      pos.categories = ['Bread'];
      pos.tables
        ..clear()
        ..add(TableModel('T1', 'Main', 4));
      pos.touch();
      host = PosHost(pos, port: 0);
      await host.start();
      link = CaptainLink(cap, creds: MemoryLinkCreds());
      await link.init();
      final err = await link.pair(hosts: ['127.0.0.1'], port: host.boundPort, secret: pos.startPairing().token, name: 'Arun');
      expect(err, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    await t.pumpWidget(StoreScope(
        store: cap, child: CaptainLinkScope(link: link, child: MaterialApp(theme: buildTheme(), home: const CaptainGate()))));
    await settle();
    expect(find.byType(CaptainHome), findsOneWidget);
    expect(find.text('Arun'), findsWidgets, reason: 'captain name from pairing');

    await t.tap(find.text('T1').first);
    await settle();
    await t.tap(find.text('Start order · 2 pax'));
    await settle(600);
    expect(pos.tables.single.parties.single.pax, 2, reason: 'seated on the POS');
    expect(find.byType(CaptainOrderScreen), findsOneWidget);

    await t.enterText(find.byType(TextField).last, 'poro');
    await settle();
    await t.tap(find.text('Porotta').first);
    await settle();
    await t.tap(find.textContaining('Review'));
    await settle();
    await t.tap(find.text('Send KOT to kitchen'));
    await settle(800);

    final o = pos.orders.single;
    expect(o.server, 'Arun');
    expect(o.lines.single.item.name, 'Porotta');
    expect(pos.kots.length, 1);
    expect(find.textContaining('sent'), findsWidgets, reason: 'captain sees the confirmation');

    await t.pump(const Duration(seconds: 5)); // let toasts and debounced saves finish
    await t.runAsync(() async {
      link.dispose();
      await host.stop();
    });
    await t.pumpWidget(const SizedBox());
    FlutterError.onError = onError;
  });
}
