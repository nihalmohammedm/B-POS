import 'dart:io';

import 'package:bistro_pos/kitchen/bell.dart';
import 'package:bistro_pos/kitchen/kds.dart';
import 'package:bistro_pos/link/captain_link.dart';
import 'package:bistro_pos/link/link_models.dart';
import 'package:bistro_pos/link/pos_host.dart';
import 'package:bistro_pos/models.dart';
import 'package:bistro_pos/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real POS, a captain and a kitchen display talking over a local socket.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // flutter_test fakes HTTP; this needs real sockets

  late Store pos, cap, kit;
  late PosHost host;
  late CaptainLink capLink, kitLink;

  Future<void> until(bool Function() ok, [String what = 'condition']) async {
    for (var i = 0; i < 100 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    expect(ok(), isTrue, reason: 'timed out waiting for $what');
  }

  Future<void> pair(CaptainLink l, String name) async {
    final offer = pos.startPairing();
    expect(await l.pair(hosts: ['127.0.0.1'], port: host.boundPort, secret: offer.token, name: name), isNull);
  }

  setUp(() async {
    final docs = Directory.systemTemp.createTempSync('bpos_kds');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => docs.path);
    m.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'), (_) async => ['none']);
    m.setMockStreamHandler(const EventChannel('dev.fluttercommunity.plus/connectivity_status'), MockStreamHandler.inline(onListen: (_, __) {}));

    pos = Store();
    cap = Store(mirror: true);
    kit = Store(mirror: true, dbName: 'bpos_kitchen');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    pos.kotGroups = const [KotGroup('g-grill', 'GR', 'Grill', 0), KotGroup('g-bread', 'BR', 'Bread', 1)];
    pos.menu
      ..clear()
      ..addAll(const [
        MenuItem(id: 'p-alfaham', code: '001', cat: 'Grill', name: 'Alfaham', price: 150, kotGroup: 'g-grill'),
        MenuItem(id: 'p-porotta', code: '003', cat: 'Bread', name: 'Porotta', price: 20, kotGroup: 'g-bread'),
      ]);
    pos.categories = ['Grill', 'Bread'];
    pos.tables
      ..clear()
      ..add(TableModel('T1', 'Main', 4));
    pos.touch();

    host = PosHost(pos, port: 0);
    await host.start();
    capLink = CaptainLink(cap, creds: MemoryLinkCreds());
    kitLink = CaptainLink(kit, creds: MemoryLinkCreds(), kind: deviceKitchen);
    await capLink.init();
    await kitLink.init();
  });

  tearDown(() async {
    capLink.dispose();
    kitLink.dispose();
    await host.stop();
    pos.dispose();
    cap.dispose();
    kit.dispose();
  });

  test('a kitchen display gets KOTs, moves them along, and can only do kitchen things', () async {
    await pair(capLink, 'Arun');
    await pair(kitLink, 'Grill');
    expect(pos.captainDevices.map((d) => d.kind), [deviceCaptain, deviceKitchen]);

    await capLink.call('seat', {'table': 'T1', 'pax': 2});
    await capLink.call('sendKot', {
      'table': 'T1',
      'party': 'A',
      'lines': [
        {'itemId': 'p-alfaham', 'qty': 1},
        {'itemId': 'p-porotta', 'qty': 2},
      ],
    });
    await until(() => kit.kots.length == 2, 'both KOTs on the kitchen display');
    final grill = kit.kots.firstWhere((k) => k.group == 'g-grill');
    expect(grill.lines.single.item.name, 'Alfaham');
    expect(grill.stage, KotStage.fresh);

    // Only the Grill section on this display.
    final prefs = KdsPrefs()..groups = {'g-grill'};
    expect(kit.kitchenKots.where((k) => prefs.shows(k.group)).map((k) => k.no), [grill.no]);

    await kitLink.call('kdsStart', {'kot': grill.no});
    expect(pos.kotByNo(grill.no)!.stage, KotStage.preparing);
    final order = pos.orderById(pos.kotByNo(grill.no)!.orderId)!;
    expect(order.lines.firstWhere((l) => l.item.id == 'p-alfaham').state, LineState.preparing,
        reason: 'kitchen progress shows on the order');

    await kitLink.call('kdsToggle', {'kot': grill.no, 'line': 0});
    expect(pos.kotByNo(grill.no)!.stage, KotStage.ready);
    await until(() => kit.kotByNo(grill.no)?.stage == KotStage.ready, 'ready mirrored');
    final n = pos.servedNotices.single;
    expect((n.station, n.kotNo, n.items), ('Grill', grill.no, '1× Alfaham'), reason: 'marking ready notifies the POS');
    await kitLink.call('kdsRecall', {'kot': grill.no});
    expect(pos.servedNotices, isEmpty, reason: 'recalled: no longer ready');
    await kitLink.call('kdsReady', {'kot': grill.no});
    await kitLink.call('kdsReady', {'kot': grill.no});
    expect(pos.servedNotices, hasLength(1), reason: 'a re-ready replaces its notice, not stacks');
    await kitLink.call('kdsBump', {'kot': grill.no});
    await until(() => kit.kotByNo(grill.no) == null, 'served ticket leaves the display');
    expect(pos.servedNotices, isEmpty, reason: 'served: notice cleared');
    await kitLink.call('kdsRecall', {'kot': grill.no});
    await kitLink.call('kdsReady', {'kot': grill.no});
    pos.dismissServed(pos.servedNotices.single.id);
    expect(pos.servedNotices, isEmpty);

    await expectLater(kitLink.call('seat', {'table': 'T1', 'pax': 1}), throwsA(isA<LinkError>()));
    await expectLater(capLink.call('kdsStart', {'kot': grill.no}), throwsA(isA<LinkError>()));
    await expectLater(kitLink.call('kdsStart', {'kot': 999}), throwsA(isA<LinkError>()));
  });

  test('a cancellation reaches the kitchen display', () async {
    await pair(capLink, 'Arun');
    await pair(kitLink, 'Bread');
    await capLink.call('seat', {'table': 'T1', 'pax': 2});
    final r = await capLink.call('sendKot', {
      'table': 'T1',
      'party': 'A',
      'lines': [
        {'itemId': 'p-porotta', 'qty': 4},
      ],
    });
    final o = pos.orderById((r['orderId'] as num).toInt())!;
    pos.cancelItem(o, o.lines.single, 1, 'Customer changed mind', by: 'Arun');
    await until(() => kit.kots.any((k) => k.kind == KotKind.cancel), 'cancellation KOT mirrored');
    final c = kit.kots.firstWhere((k) => k.kind == KotKind.cancel);
    expect(c.voided.single.qty, 1);
    expect(c.reason, 'Customer changed mind');
  });

  test('the bell is a valid WAV', () {
    final w = bellWav();
    expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(w.sublist(8, 12)), 'WAVE');
    expect(w.length, greaterThan(44 + 22050));
  });
}
