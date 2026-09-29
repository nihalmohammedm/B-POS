import 'package:bistro_pos/models.dart';
import 'package:bistro_pos/print_layout.dart';
import 'package:bistro_pos/widgets/receipt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const alfaham = MenuItem(
    id: 'p1',
    code: '001',
    cat: 'Grill',
    name: 'Alfaham',
    price: 150,
    kotGroup: 'grill',
    variants: [Variant('1 Quarter', 150), Variant('1 Full', 550, kotGroup: 'tandoor')],
  );

  test('a line takes the variant group over the product group', () {
    expect(OrderLine(item: alfaham, variant: '1 Quarter').kotGroup, 'grill');
    expect(OrderLine(item: alfaham, variant: '1 Full').kotGroup, 'tandoor');
    expect(OrderLine(item: const MenuItem(id: 'x', code: '', cat: '', name: 'Water', price: 20)).kotGroup, isNull);
  });

  test('the routed group survives a round-trip even after the menu drops it', () {
    final l = OrderLine(item: alfaham, variant: '1 Full');
    final back = OrderLine.fromJson(l.toJson()); // item rebuilt without groups
    expect(back.kotGroup, 'tandoor');
    final k = Kot.fromJson(Kot(3, 1, DateTime(2026), [l], group: 'tandoor').toJson());
    expect(k.group, 'tandoor');
    expect(MenuItem.fromJson(alfaham.toJson()), alfaham);
  });

  test('KOT prints its group name', () async {
    final d = ReceiptData(
      isKot: true,
      no: '7',
      type: OrderType.dineIn,
      where: '12',
      server: '',
      pax: 2,
      at: DateTime(2026),
      group: 'Grill',
      lines: [ReceiptLine(1, 'Alfaham', 150, [], '')],
    );
    expect(String.fromCharCodes(await receiptBytes(d, layout: PrintLayout())), contains('GRILL'));
    expect(String.fromCharCodes(await receiptBytes(d, layout: PrintLayout(kotShowGroup: false))), isNot(contains('GRILL')));
  });

  test('split KOTs say which part they are and name the others', () async {
    final d = ReceiptData(
      isKot: true,
      no: '12',
      type: OrderType.dineIn,
      where: '12',
      server: '',
      pax: 2,
      at: DateTime(2026),
      group: 'Grill',
      part: 1,
      parts: 3,
      others: ['Bread #13', 'Drinks #14'],
      lines: [ReceiptLine(1, 'Alfaham', 150, [], '')],
    );
    final text = String.fromCharCodes(await receiptBytes(d, layout: PrintLayout()));
    expect(text, contains('KOT 1 OF 3'));
    expect(text, contains('Also: BREAD #13, DRINKS #14'));
    expect(text, contains('** 2 more KOTs for this order **'));
    final k = Kot.fromJson(Kot(12, 1, DateTime(2026), [], group: 'grill', batch: [12, 13, 14]).toJson());
    expect(k.batch, [12, 13, 14]);
  });
}
