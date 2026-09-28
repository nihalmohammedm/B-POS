// Exercises the Drift schema directly (no Flutter engine needed — this is
// pure `drift` + `sqlite3`), independent of `Store` (which also pulls in
// `connectivity_plus`, a platform plugin that needs a real Flutter engine
// and can't run under plain `dart test`). This is the part of the local-db
// migration most worth verifying rigorously: does data actually round-trip
// through Drift, and does it survive closing and reopening the same file —
// the entire point of moving off shared_preferences.
import 'dart:convert';
import 'dart:io';

import 'package:bistro_pos/db/app_database.dart';
import 'package:bistro_pos/models.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('menu items round-trip through JSON + Drift', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    const item = MenuItem(
      id: 'p1',
      code: '001',
      cat: 'Grill',
      name: 'Alfaham',
      price: 150,
      veg: false,
      kitchenNotes: ['Dry', 'Juicy'],
    );
    await db.into(db.menuItemRows).insert(MenuItemRowsCompanion.insert(id: item.id, json: jsonEncode(item.toJson())));

    final rows = await db.select(db.menuItemRows).get();
    expect(rows, hasLength(1));
    final loaded = MenuItem.fromJson(jsonDecode(rows.single.json) as Map<String, dynamic>);
    expect(loaded.name, 'Alfaham');
    expect(loaded.kitchenNotes, ['Dry', 'Juicy']);
    expect(loaded.price, 150);

    await db.close();
  });

  test('orders, tables and settings survive closing and reopening the same file', () async {
    final dir = await Directory.systemTemp.createTemp('drift_test');
    final file = File('${dir.path}/test.sqlite');
    try {
      // Session 1: write.
      var db = AppDatabase.forTesting(NativeDatabase(file));
      final table = TableModel('T1', 'Tables', 4);
      table.parties.add(Party('A', 2, orderId: 1));
      await db
          .into(db.diningTableRows)
          .insert(DiningTableRowsCompanion.insert(id: table.id, json: jsonEncode(table.toJson())));

      final order = Order(id: 1, type: OrderType.dineIn, tableId: 'T1', partyKey: 'A', pax: 2);
      order.lines.add(OrderLine(
        item: const MenuItem(id: 'p1', code: '001', cat: 'Grill', name: 'Alfaham', price: 150),
        qty: 1,
        note: 'Extra spicy',
      ));
      await db.into(db.orderRows).insert(OrderRowsCompanion.insert(id: const Value(1), json: jsonEncode(order.toJson())));

      await db.into(db.settingsRows).insert(SettingsRowsCompanion.insert(key: 'orderSeq', value: '1'));
      await db.close();

      // Session 2: fresh AppDatabase instance pointed at the same file — simulates an app restart.
      db = AppDatabase.forTesting(NativeDatabase(file));

      final tableRows = await db.select(db.diningTableRows).get();
      expect(tableRows, hasLength(1));
      final loadedTable = TableModel.fromJson(jsonDecode(tableRows.single.json) as Map<String, dynamic>);
      expect(loadedTable.parties, hasLength(1));
      expect(loadedTable.parties.single.pax, 2);

      final orderRows = await db.select(db.orderRows).get();
      expect(orderRows, hasLength(1));
      final loadedOrder = Order.fromJson(jsonDecode(orderRows.single.json) as Map<String, dynamic>);
      expect(loadedOrder.lines.single.note, 'Extra spicy');
      expect(loadedOrder.lines.single.unitPrice, 150);

      final seqRow = await (db.select(db.settingsRows)..where((t) => t.key.equals('orderSeq'))).getSingle();
      expect(seqRow.value, '1');

      await db.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('replacing a table (delete-all + insert-all in a batch) leaves only the new rows', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.batch((b) {
      b.insertAll(db.itemOffRows, [
        ItemOffRowsCompanion.insert(id: 'a'),
        ItemOffRowsCompanion.insert(id: 'b'),
      ]);
    });
    expect(await db.select(db.itemOffRows).get(), hasLength(2));

    await db.batch((b) {
      b.deleteAll(db.itemOffRows);
      b.insertAll(db.itemOffRows, [ItemOffRowsCompanion.insert(id: 'c')]);
    });
    final rows = await db.select(db.itemOffRows).get();
    expect(rows.map((r) => r.id), ['c']);

    await db.close();
  });
}
