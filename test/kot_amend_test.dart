import 'package:bistro_pos/models.dart';
import 'package:bistro_pos/print_layout.dart';
import 'package:bistro_pos/widgets/receipt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const m = MenuItem(id: 'p1', code: '003', cat: 'Bread', name: 'Porotta', price: 20);

  test('cancelled units reduce totals but keep the ordered qty', () {
    final l = OrderLine(item: m, qty: 4)..cancelledQty = 1;
    expect(l.qty, 4);
    expect(l.activeQty, 3);
    expect(l.total, 60);
    final back = OrderLine.fromJson(l.toJson());
    expect(back.cancelledQty, 1);
    expect(back.activeQty, 3);
  });

  test('KOT kind and stage follow voided/live lines', () {
    final live = OrderLine(item: m, qty: 2);
    final gone = OrderLine(item: m, qty: 2)..cancelledQty = 2;
    expect(Kot(1, 1, DateTime.now(), [live]).kind, KotKind.order);
    expect(Kot(2, 1, DateTime.now(), [], voided: [gone]).kind, KotKind.cancel);
    expect(Kot(3, 1, DateTime.now(), [live], voided: [gone]).kind, KotKind.modify);
    // A KOT whose only line was fully cancelled leaves the kitchen screen.
    expect(Kot(4, 1, DateTime.now(), [gone]).stage, KotStage.done);
    final k = Kot.fromJson(Kot(5, 1, DateTime.now(), [], voided: [gone], reason: 'Out of stock', by: 'Asha').toJson());
    expect((k.kind, k.reason, k.by), (KotKind.cancel, 'Out of stock', 'Asha'));
  });

  test('order keeps cancellation audit and totals only live items', () {
    final o = Order(id: 1, type: OrderType.takeaway);
    o.lines.add(OrderLine(item: m, qty: 4)..cancelledQty = 1);
    o.cancellations.add(ItemCancellation(
        itemName: 'Porotta', optText: '', qty: 1, unitPrice: 20, reason: 'Duplicate order', by: 'Asha', kotNo: 9, at: DateTime(2026)));
    final back = Order.fromJson(o.toJson());
    expect(back.itemCount, 3);
    expect(back.subtotal, 60);
    expect(back.cancellations.single.reason, 'Duplicate order');
  });

  test('cancellation and modified KOTs render to ESC/POS', () async {
    ReceiptData kot(KotKind kind) => ReceiptData(
          isKot: true,
          no: '12',
          type: OrderType.dineIn,
          where: '12',
          server: 'Captain 1',
          pax: 2,
          at: DateTime(2026, 9, 29, 13, 5),
          kind: kind,
          reason: 'Customer changed mind',
          by: 'Asha',
          voided: [ReceiptLine(2, 'Porotta', 20, [], '')],
          lines: kind == KotKind.modify ? [ReceiptLine(2, 'Porotta', 20, [], 'Well done')] : [],
        );
    for (final kind in [KotKind.cancel, KotKind.modify]) {
      final bytes = await receiptBytes(kot(kind), layout: PrintLayout());
      final text = String.fromCharCodes(bytes);
      expect(text, contains(kind == KotKind.cancel ? '*** CANCELLED ***' : '*** ITEM CHANGED ***'));
      expect(text, contains('-2x'));
      expect(text, contains('Reason: Customer changed mind'));
      if (kind == KotKind.modify) expect(text, contains('MAKE INSTEAD'));
    }
  });

  test('bill print time survives a restart; old orders without it still load', () {
    final o = Order(id: 7, type: OrderType.dineIn, tableId: 'T1', partyKey: 'A')
      ..billed = true
      ..billNo = 'B12'
      ..billedAt = DateTime(2026, 9, 29, 13, 5);
    expect(Order.fromJson(o.toJson()).billedAt, DateTime(2026, 9, 29, 13, 5));
    final legacy = o.toJson()..remove('billedAt');
    expect(Order.fromJson(legacy).billedAt, isNull);
  });

  test('takeaway paid up front counts as paid once payments cover the total', () {
    final o = Order(id: 9, type: OrderType.takeaway);
    o.lines.add(OrderLine(item: m, qty: 5)); // 100 + 5% = 105
    expect(o.isPaid, isFalse);
    o.payments.add(const Payment('UPI', 100));
    expect(o.isPaid, isFalse); // short by 5
    o.payments.add(const Payment('Cash', 5, 10));
    expect(o.isPaid, isTrue);
    expect(Order.fromJson(o.toJson()).isPaid, isTrue);
  });
}
