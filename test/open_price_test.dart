import 'package:BPOS/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fish = MenuItem(
    id: 'p1',
    code: '101',
    cat: 'Seafood',
    name: 'Pomfret Fry',
    price: 0,
    openPrice: true,
    variants: [Variant('Small', 300), Variant('Large', 600)],
    addons: [Addon('Extra masala', 40)],
  );

  test('typed price replaces the item/size price, add-ons go on top', () {
    final l = OrderLine(item: fish, variant: 'Large', addons: ['Extra masala'], qty: 2).priced(780);
    expect(l.unitPrice, 820);
    expect(l.total, 1640);
    expect(l.variant, 'Large');
    expect(l.qty, 2);
  });

  test('a priced line keeps its price through copy and JSON', () {
    final l = OrderLine(item: fish, variant: 'Small').priced(455.5);
    expect(l.copy().unitPrice, 455.5);
    expect(OrderLine.fromJson(l.toJson()).unitPrice, 455.5);
  });

  test('open/daily price flags survive the menu cache', () {
    const daily = MenuItem(id: 'p2', code: '', cat: 'Seafood', name: 'Prawns', price: 420, dailyPrice: true);
    final back = MenuItem.fromJson(fish.toJson());
    expect(back.openPrice, isTrue);
    expect(back, fish);
    expect(MenuItem.fromJson(daily.toJson()).dailyPrice, isTrue);
    expect(MenuItem.fromJson({'id': 'x', 'code': '', 'cat': 'c', 'name': 'n', 'price': 1}).openPrice, isFalse);
  });

  test('the menu price of the item or chosen size is the minimum', () {
    expect(fish.basePrice('Large'), 600);
    expect(fish.basePrice('Small'), 300);
    expect(fish.basePrice(null), 0);
  });
}
