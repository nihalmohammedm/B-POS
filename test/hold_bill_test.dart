import 'dart:io';

import 'package:BPOS/models.dart';
import 'package:BPOS/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const m = MenuItem(id: 'p1', code: '003', cat: 'Bread', name: 'Porotta', price: 20);
  late Store s;

  setUp(() async {
    final docs = Directory.systemTemp.createTempSync('bpos_hold');
    final b = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    b.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => docs.path);
    b.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'), (_) async => ['none']);
    b.setMockStreamHandler(const EventChannel('dev.fluttercommunity.plus/connectivity_status'), MockStreamHandler.inline(onListen: (_, __) {}));
    s = Store();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    s.tables
      ..clear()
      ..add(TableModel('5', 'Main', 4));
  });

  Order seated(TableModel t) {
    final p = s.seatParty(t, 2);
    final o = s.ensurePartyOrder(t, p);
    o.lines.add(OrderLine(item: m, qty: 2));
    return o;
  }

  test('a held bill clears the table but stays open to settle', () {
    final t = s.tables.first;
    final o = seated(t);
    expect(s.holdBill(o), isFalse, reason: 'bill must be printed first');

    s.printBill(o);
    final label = s.labelOf(o);
    expect(s.holdBill(o), isTrue);

    expect(t.parties, isEmpty, reason: 'table is free again');
    expect(s.orders, contains(o));
    expect(s.heldOrders, [o]);
    expect(s.awaitingPayment, contains(o));
    expect(s.labelOf(o), label);
    expect(s.holdBill(o), isFalse, reason: 'already held');

    // A new party can sit and order at the same table without touching the held bill.
    final o2 = seated(t);
    expect(o2.id, isNot(o.id));
    expect(s.orderOfParty(t, t.parties.single), o2);
    expect(s.labelOf(o), label);

    // Survives a restart and settles like any other bill.
    final back = Order.fromJson(o.toJson());
    expect((back.held, back.heldLabel, back.heldAt), (true, label, o.heldAt));
    s.settle(o, payments: [Payment('Cash', o.total)]);
    expect(s.orders, isNot(contains(o)));
    expect(s.history, contains(o));
    expect(t.parties.single.orderId, o2.id, reason: 'settling must not free the new party');
  });
}
