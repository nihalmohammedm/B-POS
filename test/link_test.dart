import 'dart:async';
import 'dart:io';

import 'package:bistro_pos/link/captain_link.dart';
import 'package:bistro_pos/link/pos_host.dart';
import 'package:bistro_pos/models.dart';
import 'package:bistro_pos/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real POS and a real captain talking over a local socket.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // flutter_test fakes HTTP; this needs real sockets

  late Store pos, cap;
  late PosHost host;
  late CaptainLink link;

  Future<void> until(bool Function() ok, [String what = 'condition']) async {
    for (var i = 0; i < 100 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    expect(ok(), isTrue, reason: 'timed out waiting for $what');
  }

  setUp(() async {
    final docs = Directory.systemTemp.createTempSync('bpos_link');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => docs.path);
    m.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'), (_) async => ['none']);
    m.setMockStreamHandler(const EventChannel('dev.fluttercommunity.plus/connectivity_status'), MockStreamHandler.inline(onListen: (_, __) {}));

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
    pos.outletName = 'Bolgatty';
    pos.touch();

    host = PosHost(pos, port: 0);
    await host.start();
    link = CaptainLink(cap, creds: MemoryLinkCreds());
    await link.init();
    expect(link.state, LinkState.unpaired);
  });

  tearDown(() async {
    link.dispose();
    await host.stop();
    pos.dispose();
    cap.dispose();
  });

  test('pair with the typed code, then seat, send a KOT, retry it, and ask for the bill', () async {
    final offer = pos.startPairing();
    final typed = '${offer.code.substring(0, 4)}-${offer.code.substring(4)}'.toLowerCase();
    final err = await link.pair(hosts: ['127.0.0.1'], port: host.boundPort, secret: typed, name: 'Arun');
    expect(err, isNull);
    expect(link.state, LinkState.online);
    expect(pos.pairing, isNull, reason: 'the code works once');
    expect(pos.captainDevices.single.name, 'Arun');
    expect(pos.captainDevices.single.sessionHash, isNot(contains(link.creds is MemoryLinkCreds ? (link.creds as MemoryLinkCreds).v!['session']! : '')),
        reason: 'the POS keeps only a hash of the session');

    await until(() => cap.tables.isNotEmpty && cap.menu.isNotEmpty, 'first snapshot');
    expect(cap.outletName, 'Bolgatty');

    final seat = await link.call('seat', {'table': 'T1', 'pax': 2});
    expect(seat['party'], 'A');
    await until(() => cap.tables.single.parties.length == 1, 'seated party mirrored');

    final args = {
      'req': 'r1',
      'table': 'T1',
      'party': 'A',
      'lines': [
        {'itemId': 'p-porotta', 'itemName': 'Porotta', 'qty': 2, 'note': 'Well done'}
      ],
    };
    final sent = await link.call('sendKot', args);
    final again = await link.call('sendKot', args); // captain retry after a dropped reply
    expect(again, sent);
    final o = pos.orderById((sent['orderId'] as num).toInt())!;
    expect(o.server, 'Arun');
    expect(o.lines.single.qty, 2);
    expect(pos.kots.length, 1, reason: 'the retry did not make a second KOT');
    await until(() => cap.orders.isNotEmpty, 'order mirrored');

    await link.call('requestBill', {'orderId': o.id});
    expect(pos.billRequests.single.captain, 'Arun');
    await until(() => cap.requestedBills.contains(o.id), 'bill request mirrored');

    await expectLater(link.call('seat', {'table': 'T1', 'pax': 9}), throwsA(isA<LinkError>()));
  });

  test('a wrong code is refused; a removed phone is sent back to pairing', () async {
    final offer = pos.startPairing();
    expect(await link.pair(hosts: ['127.0.0.1'], port: host.boundPort, secret: 'WRONGCOD', name: 'Arun'), contains('wrong'));
    expect(await link.pair(hosts: ['127.0.0.1'], port: host.boundPort, secret: offer.token, name: 'Arun'), isNull);

    pos.removeCaptain(pos.captainDevices.single.id);
    await until(() => link.state == LinkState.unpaired, 'revoked captain unpaired');
    expect(await link.creds.load(), isNull);
  });

  test('reconnects on its own after the POS restarts', () async {
    final offer = pos.startPairing();
    expect(await link.pair(hosts: ['127.0.0.1'], port: host.boundPort, secret: offer.token, name: 'Arun'), isNull);
    final port = host.boundPort;
    await host.stop();
    await until(() => link.state == LinkState.offline, 'offline noticed');
    await expectLater(link.call('seat', {'table': 'T1', 'pax': 1}), throwsA(isA<LinkError>()));
    host = PosHost(pos, port: port);
    await host.start();
    link.reconnect();
    await until(() => link.state == LinkState.online, 'back online');
  });

  test('a freshly started POS still knows its captains (no re-pairing)', () async {
    final offer = pos.startPairing();
    expect(await link.pair(hosts: ['127.0.0.1'], port: host.boundPort, secret: offer.token, name: 'Arun'), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 300)); // captain list saved
    final port = host.boundPort;
    await host.stop();
    await until(() => link.state == LinkState.offline, 'offline noticed');
    await Future<void>.delayed(const Duration(milliseconds: 300)); // old POS's last write lands

    // A new POS process on the same database: the host must not accept the
    // captain's hello before the saved captains are loaded.
    pos.dispose();
    pos = Store(); // tearDown disposes it
    host = PosHost(pos, port: port);
    final starting = host.start();
    link.reconnect();
    await starting;
    await until(() => link.state == LinkState.online, 'logged straight back in');
    expect(await link.creds.load(), isNotNull, reason: 'the pairing survived the restart');
  });

  test('finds the POS on the Wi-Fi after its address changes', () async {
    await host.stop();
    host = PosHost(pos, port: 18787); // a fixed port, so the POS answers discovery broadcasts
    await host.start();
    final offer = pos.startPairing();
    expect(await link.pair(hosts: ['127.0.0.1'], port: 18787, secret: offer.token, name: 'Arun'), isNull);

    // The phone restarts remembering an address the POS no longer has.
    final saved = Map.of((link.creds as MemoryLinkCreds).v!)..['host'] = '192.0.2.1';
    link.dispose();
    link = CaptainLink(cap, creds: MemoryLinkCreds()..v = saved);
    await link.init();
    expect(link.state, LinkState.online);
    expect(link.host, isNot('192.0.2.1'));
    expect((link.creds as MemoryLinkCreds).v!['host'], link.host, reason: 'the new address is saved for next time');
  }, timeout: const Timeout(Duration(seconds: 40)));
}
