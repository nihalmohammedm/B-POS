import 'package:flutter_test/flutter_test.dart';
import 'package:BPOS/sync/web_order_api.dart';

void main() {
  test('WebOrder parses a pending order with variants and add-ons', () {
    final w = WebOrder.fromJson({
      'id': 'w1',
      'order_number': 7,
      'order_type': 'dine_in',
      'customer_name': 'Arun',
      'customer_phone': '9876543210',
      'table_label': '12',
      'notes': null,
      'created_at': '2026-10-07T10:00:00Z',
      'web_order_items': [
        {
          'product_id': 'p1',
          'item_name': 'Alfaham',
          'variant_name': '1 Half',
          'modifiers': [
            {'name': 'Mayo', 'price': 10}
          ],
          'quantity': 2,
          'unit_price': 310,
        },
      ],
    });
    expect(w.dineIn, isTrue);
    expect(w.table, '12');
    expect(w.notes, '');
    expect(w.lines.single.addons, ['Mayo']);
    expect(w.total, 620);
  });
}
